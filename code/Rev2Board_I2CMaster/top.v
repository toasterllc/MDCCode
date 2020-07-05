`timescale 1ns/1ps
`include "../ClockGen.v"

module PIXI2CMaster #(
    parameter ClkFreq = 12000000,   // `clk` frequency
    parameter I2CClkFreq = 400000   // `i2c_clk` frequency
)(
    input wire          clk,
    
    // Command port
    input wire          cmd_trigger,
    input wire[6:0]     cmd_slaveAddr,
    input wire          cmd_write,
    input wire[15:0]    cmd_addr,
    input wire[15:0]    cmd_writeData,
    output reg[15:0]    cmd_readData = 0,
    input wire          cmd_dataLen, // 0 (1 byte) or 1 (2 bytes)
    output reg          cmd_done = 0,
    
    // i2c port
    output reg          i2c_clk = 0,
    inout wire          i2c_data
);
    // Delay() returns the value to store in a counter, such that when
    // the counter reaches 0, `t` nanoseconds has elapsed.
    // `sub` is subtracted from that value, with the result clipped to zero.
    function [63:0] Delay;
        input [63:0] t;
        input [63:0] sub;
        begin
            Delay = (t*ClkFreq)/1000000000;
            if (Delay >= sub) Delay = Delay-sub;
            else Delay = 0;
        end
    endfunction
    
    function [63:0] CeilDiv;
        input [63:0] n;
        input [63:0] d;
        begin
            CeilDiv = (n+d-1)/d;
        end
    endfunction
    
    // I2CQuarterCycleDelay: number of `clk` cycles for a quarter of the `i2c_clk` cycle to elapse.
    // CeilDiv() is necessary to perform the quarter-cycle calculation, so that the
    // division is ceiled to the nearest nanosecond. (Ie -- slower than I2CClkFreq is OK, faster is not.)
    localparam I2CQuarterCycleDelay = Delay(CeilDiv(1000000000, 4*I2CClkFreq), 0);
    
    // Width of `delay`
    localparam DelayWidth = $clog2(I2CQuarterCycleDelay+1);
    
    
    
    
    
    reg[1:0] state = 0;
    reg[1:0] ackState = 0;
    reg[8:0] dataOutShiftReg = 0; // Low bit is sentinel
    wire dataOut = dataOutShiftReg[8];
    wire dataIn;
    reg[DelayWidth-1:0] delay = 0;
    
    `ifdef SIM
        // TODO: implement sim version 
    `else
        // For synthesis, we have to use a SB_IO_OD for the open-drain output
        SB_IO_OD #(
            .PIN_TYPE(6'b1010_01),
        ) dqio (
            .PACKAGE_PIN(i2c_data),
            .OUTPUT_ENABLE(1),
            .D_OUT_0(dataOut),
            .D_IN_0(dataIn)
        );
    `endif
    
    
    localparam StateIdle = 0;
    localparam StateStart = 20;
    localparam StateShiftOut = 40;
    localparam StateRegAddr = 60;
    localparam StateWriteData = 80;
    localparam StateReadData = 100;
    localparam StateStop = 120;
    always @(posedge clk) begin
        if (delay) begin
            delay <= delay-1;
        
        end else begin
            case (state)
            // Idle (SDA=1, SCL=1)
            StateIdle: begin
                i2c_clk <= 1;
                dataOutShiftReg <= ~0;
                // TODO: don't we actually want to wait a 1/2 cycle in this case?
                delay <= I2CQuarterCycleDelay;
                state <= StateStart;
            end
            
            
            
            
            
            // Accept command,
            // Issue start condition (SDA=1->0 while SCL=1),
            // Delay 1/4 cycle
            StateStart: begin
                if (cmd_trigger) begin
                    dataOutShiftReg <= 0; // Start condition
                    delay <= I2CQuarterCycleDelay;
                    state <= StateStart+1;
                end
            end
            
            // SCL=0,
            // Delay 1/4 cycle
            StateStart+1: begin
                i2c_clk <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateStart+2;
            end
            
            // Load slave address/direction into shift register,
            // SDA=first bit,
            // Delay 1/4 cycle
            // After ACK, state=StateRegAddr
            StateStart+2: begin
                dataOutShiftReg <= {cmd_slaveAddr, !cmd_write, 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                ackState <= StateRegAddr;
            end
            
            
            
            
            
            
            // SCL=1,
            // Delay 1/4 cycle
            StateShiftOut: begin
                i2c_clk <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut+1;
            end
            
            // Delay 1/4 cycle (for a total of 1/2 cycles
            // that SCL=1 while SDA is constant)
            StateShiftOut+1: begin
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut+2;
            end
            
            // SCL=0,
            // Delay 1/4 cycle
            StateShiftOut+2: begin
                i2c_clk <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut+3;
            end
            
            // SDA=next bit,
            // Delay 1/4 cycle
            StateShiftOut+3: begin
                // Continue shift loop if there's more data
                if (dataOutShiftReg[7:0] != 8'b10000000) begin
                    dataOutShiftReg <= dataOutShiftReg<<1;
                    delay <= I2CQuarterCycleDelay;
                    state <= StateShiftOut;
                
                // Otherwise, we're done shifting:
                // Next state after 1/4 cycle
                end else begin
                    dataOutShiftReg <= ~0;
                    delay <= I2CQuarterCycleDelay;
                    state <= StateShiftOut+4;
                end
            end
            
            // SCL=1,
            // Delay 1/4 cycle
            StateShiftOut+4: begin
                i2c_clk <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut+5;
            end
            
            // Check for ACK (SDA=0),
            // Delay 1/4 cycle
            StateShiftOut+5: begin
                // Handle ACK
                if (!dataIn) begin
                    delay <= I2CQuarterCycleDelay;
                    state <= ackState;
                
                // Handle NACK
                end else begin
                    delay <= I2CQuarterCycleDelay;
                    state <= StateStop;
                end
            end
            
            
            
            
            
            
            
            // SCL=0,
            // Delay 1/4 cycle
            StateRegAddr: begin
                i2c_clk <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateRegAddr+1;
            end
            
            // Shift out high 8 bits of address
            StateRegAddr+1: begin
                dataOutShiftReg <= {cmd_addr[15:8], 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                ackState <= StateRegAddr+2;
            end
            
            // Shift out low 8 bits of address
            StateRegAddr+2: begin
                dataOutShiftReg <= {cmd_addr[7:0], 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                if (cmd_write) begin
                    ackState <= (cmd_dataLen ? StateWriteData : StateWriteData+1);
                end else begin
                    ackState <= (cmd_dataLen ? StateReadData : StateReadData+1);
                end
            end
            
            
            
            
            
            
            // Shift out high 8 bits of data
            StateWriteData: begin
                dataOutShiftReg <= {cmd_writeData[15:8], 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                ackState <= (cmd_dataLen ? StateWriteData+1 : StateStop);
            end
            
            // Shift out low 8 bits of data
            StateWriteData+1: begin
                dataOutShiftReg <= {cmd_writeData[7:0], 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                ackState <= StateStop;
            end
            
            
            
            
            
            // SCL=0,
            // Delay 1/4 cycle
            StateStop: begin
                i2c_clk <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateStop+1;
            end
            
            // SDA=0,
            // Delay 1/4 cycle
            StateStop+1: begin
                dataOutShiftReg <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateStop+2;
            end
            
            // SCL=1,
            // Delay 1/4 cycle,
            // Issue stop condition (SDA=0->1 while SCL=1) by going to StateIdle
            StateStop+2: begin
                i2c_clk <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= StateStop+3;
            end
            
            StateStop+3: begin
                cmd_done <= 1;
                state <= StateStop+4;
                // No delay! We only want cmd_done=1 for one cycle.
            end
            
            StateStop+4: begin
                cmd_done <= 0;
                state <= StateIdle;
            end
            endcase
        end
    end
endmodule





module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0,
    
    output wire         pix_sclk,
    inout wire          pix_sdata
);
        //     // ====================
        //     // Clock PLL (54.750 MHz)
        //     // ====================
        //     localparam ClkFreq = 54750000;
        //     wire clk;
        //     ClockGen #(
        //         .FREQ(ClkFreq),
        // .DIVR(0),
        // .DIVF(72),
        // .DIVQ(4),
        // .FILTER_RANGE(1)
        //     ) cg(.clk12mhz(clk12mhz), .clk(clk));
        //
        //     // I2CMaster #(
        //     //     .ClkFreq(ClkFreq),
        //     //     .I2CClkFreq(400000)
        //     // ) i2cMaster(
        //     //     clk(clk),
        //     //
        //     //     cmd_trigger(),
        //     //     cmd_addr(),
        //     //     cmd_write(),
        //     //     cmd_writeData(),
        //     //     cmd_readData(),
        //     //     cmd_done(),
        //     //
        //     //     i2c_clk(pix_sclk),
        //     //     i2c_data(pix_sdata)
        //     // );
        //     //
        //
        //     // ====================
        //     // Main
        //     // ====================
        //     always @(posedge clk) begin
        //     end
    
endmodule

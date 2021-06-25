`ifndef ImgI2CMaster_v
`define ImgI2CMaster_v

`include "Util.v"
`include "ToggleAck.v"

module ImgI2CMaster #(
    parameter ClkFreq       = 24_000_000,   // `clk` frequency
    parameter I2CClkFreq    = 400_000       // `i2c_clk` frequency
)(
    input wire          clk,
    
    // Command port
    input wire[6:0]     cmd_slaveAddr,
    input wire          cmd_write,
    input wire[15:0]    cmd_regAddr,
    input wire          cmd_dataLen, // 0: 1 byte, 1: 2 bytes
    input wire[15:0]    cmd_writeData,
    input wire          cmd_trigger, // Toggle
    
    // Status port
    output reg          status_done = 0, // Toggle
    output reg          status_err = 0,
    output wire[15:0]   status_readData,
    
    // I2C port
    output wire         i2c_clk,
    inout wire          i2c_data
);
    // I2CQuarterCycleDelay: number of `clk` cycles for a quarter of the `i2c_clk` cycle to elapse.
    // DivCeil() is necessary to perform the quarter-cycle calculation, so that the
    // division is ceiled to the nearest clock cycle. (Ie -- slower than I2CClkFreq is OK, faster is not.)
    // -1 for the value that should be stored in a counter.
    localparam I2CQuarterCycleDelay = `DivCeil(ClkFreq, 4*I2CClkFreq)-1;
    
    // Width of `delay`
    localparam DelayWidth = $clog2(I2CQuarterCycleDelay+1);
    
    localparam State_Idle       = 0;    // +0
    localparam State_Start      = 1;    // +2
    localparam State_ShiftOut   = 4;    // +7
    localparam State_RegAddr    = 12;   // +1
    localparam State_WriteData  = 14;   // +1
    localparam State_ReadData   = 16;   // +8
    localparam State_ACK        = 25;   // +3
    localparam State_StopOK     = 29;   // +0
    localparam State_StopFail   = 30;   // +0
    localparam State_Stop       = 31;   // +2
    localparam State_Count      = 34;
    
    reg[$clog2(State_Count)-1:0] state = 0;
    reg[$clog2(State_Count)-1:0] nextState = 0;
    reg ack = 0;
    reg[7:0] dataOutShiftReg = 0;
    wire dataOut = dataOutShiftReg[7];
    reg[2:0] dataOutCounter = 0;
    reg[15:0] dataInShiftReg = 0;
    reg[3:0] dataInCounter = 0;
    assign status_readData = dataInShiftReg[15:0];
    wire dataIn;
    reg[DelayWidth-1:0] delay = 0;
    reg clkOut = 0;
    
    `ToggleAck(trigger, triggerAck, cmd_trigger, posedge, clk);
    
    // ====================
    // i2c_clk
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b0101_01)
    ) SB_IO_i2c_clk (
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(i2c_clk),
        .D_OUT_0(clkOut)
    );
    
    // ====================
    // i2c_data
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_i2c_data (
        .INPUT_CLK(clk),
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(i2c_data),
        .OUTPUT_ENABLE(!dataOut),
        .D_OUT_0(dataOut),
        .D_IN_0(dataIn)
    );
    
    always @(posedge clk) begin
        if (delay) begin
            delay <= delay-1;
        
        end else begin
            case (state)
            
            // Idle (SDA=1, SCL=1)
            State_Idle: begin
                clkOut <= 1;
                dataOutShiftReg <= ~0;
                delay <= I2CQuarterCycleDelay;
                state <= State_Start;
            end
            
            
            
            
            
            
            
            
            
            // Accept command,
            // Issue start condition (SDA=1->0 while SCL=1),
            // Delay 1/4 cycle
            State_Start: begin
                if (trigger) begin
                    triggerAck <= !triggerAck; // Acknowlege the trigger
                    dataOutShiftReg <= 0; // Start condition
                    delay <= I2CQuarterCycleDelay;
                    state <= State_Start+1;
                end
            end
            
            // SCL=0,
            // Delay 1/4 cycle
            State_Start+1: begin
                clkOut <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= State_Start+2;
            end
            
            // Load slave address/direction into shift register,
            // SDA=first bit,
            // Delay 1/4 cycle
            // After ACK, state=State_RegAddr
            // *** Note that dir=0 (write) on the initial transmission, even when reading.
            // *** If we intend to read, we perform a second START condition after
            // *** providing the slave address, and then provide the slave address/direction
            // *** again. This second time is when provide dir=1 (read).
            // *** See i2c docs for more information on how reads are performed.
            State_Start+2: begin
                dataOutShiftReg <= {cmd_slaveAddr, 1'b0 /* dir=0 (write, see comment above) */};
                dataOutCounter <= 7;
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut;
                nextState <= State_RegAddr;
            end
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            // SCL=1,
            // Delay 1/4 cycle
            State_ShiftOut: begin
                clkOut <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut+1;
            end
            
            // Delay 1/4 cycle (for a total of 1/2 cycles
            // that SCL=1 while SDA is constant)
            State_ShiftOut+1: begin
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut+2;
            end
            
            // SCL=0,
            // Delay 1/4 cycle
            State_ShiftOut+2: begin
                clkOut <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut+3;
            end
            
            // SDA=next bit,
            // Delay 1/4 cycle
            State_ShiftOut+3: begin
                dataOutCounter <= dataOutCounter-1;
                // Continue shift loop if there's more data
                if (dataOutCounter) begin
                    dataOutShiftReg <= dataOutShiftReg<<1;
                    delay <= I2CQuarterCycleDelay;
                    state <= State_ShiftOut;
                
                // Otherwise, we're done shifting:
                // Next state after 1/4 cycle
                end else begin
                    dataOutShiftReg <= ~0;
                    delay <= I2CQuarterCycleDelay;
                    state <= State_ShiftOut+4;
                end
            end
            
            // SCL=1,
            // Delay 1/4 cycle
            State_ShiftOut+4: begin
                clkOut <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut+5;
            end
            
            // Check for ACK (SDA=0) or NACK (SDA=1),
            // Delay 1/4 cycle
            State_ShiftOut+5: begin
                delay <= I2CQuarterCycleDelay;
                state <= (!dataIn ? State_ShiftOut+6 : State_ShiftOut+7);
            end
            
            // Handle ACK:
            // SCL=0,
            // Delay 1/4 cycle,
            // Go to `nextState`
            State_ShiftOut+6: begin
                clkOut <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= nextState;
            end
            
            // Handle NACK:
            // SCL=0,
            // Delay 1/4 cycle,
            // Go to State_Stop
            State_ShiftOut+7: begin
                clkOut <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= State_StopFail;
            end
            
            
            
            
            
            
            
            // Shift out high 8 bits of address
            State_RegAddr: begin
                dataOutShiftReg <= cmd_regAddr[15:8];
                dataOutCounter <= 7;
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut;
                nextState <= State_RegAddr+1;
            end
            
            // Shift out low 8 bits of address
            State_RegAddr+1: begin
                dataOutShiftReg <= cmd_regAddr[7:0];
                dataOutCounter <= 7;
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut;
                if (cmd_write) begin
                    $display("[ImgI2CMaster] WRITE");
                    nextState <= (cmd_dataLen ? State_WriteData : State_WriteData+1);
                end else begin
                    $display("[ImgI2CMaster] READ");
                    nextState <= (cmd_dataLen ? State_ReadData : State_ReadData+1);
                end
            end
            
            
            
            
            
            
            
            
            
            // Shift out high 8 bits of data
            State_WriteData: begin
                dataOutShiftReg <= cmd_writeData[15:8];
                dataOutCounter <= 7;
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut;
                nextState <= State_WriteData+1;
            end
            
            // Shift out low 8 bits of data
            State_WriteData+1: begin
                dataOutShiftReg <= cmd_writeData[7:0];
                dataOutCounter <= 7;
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut;
                nextState <= State_StopOK;
            end
            
            
            
            
            
            
            
            
            
            
            
            // SDA=1,
            // Delay 1/4 cycle,
            State_ReadData: begin
                dataOutShiftReg <= ~0;
                delay <= I2CQuarterCycleDelay;
                state <= State_ReadData+1;
            end
            
            // SCL=1,
            // Delay 1/4 cycle
            State_ReadData+1: begin
                clkOut <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= State_ReadData+2;
            end
            
            // Issue repeated start condition (SDA=1->0 while SCL=1),
            // Delay 1/4 cycle
            State_ReadData+2: begin
                dataOutShiftReg <= 0; // Start condition
                delay <= I2CQuarterCycleDelay;
                state <= State_ReadData+3;
            end
            
            // SCL=0,
            // Delay 1/4 cycle
            State_ReadData+3: begin
                clkOut <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= State_ReadData+4;
            end
            
            // Shift out the slave address and direction (read), again.
            // The only difference is this time we actually specify the read direction,
            // whereas the first time we always specify the write direction. See comment
            // in the State_Start state for more info.
            State_ReadData+4: begin
                dataOutShiftReg <= {cmd_slaveAddr, 1'b1 /* dir=1 (read) */};
                dataOutCounter <= 7;
                dataInCounter <= (cmd_dataLen ? 15 : 7);
                delay <= I2CQuarterCycleDelay;
                state <= State_ShiftOut;
                nextState <= State_ReadData+5;
            end
            
            // SDA=1 (necessary since we return to this state after an ACK,
            //        so we need to relinquish SDA so the slave can control it),
            // Delay 1/4 cycle
            State_ReadData+5: begin
                dataOutShiftReg <= ~0;
                delay <= I2CQuarterCycleDelay;
                state <= State_ReadData+6;
            end
            
            // SCL=1,
            // Delay 1/4 cycle
            State_ReadData+6: begin
                clkOut <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= State_ReadData+7;
            end
            
            // Read another bit
            // Delay 1/4 cycle
            State_ReadData+7: begin
                dataInShiftReg <= (dataInShiftReg<<1)|dataIn;
                delay <= I2CQuarterCycleDelay;
                state <= State_ReadData+8;
            end
            
            // SCL=0,
            // Check if we need to ACK or if we're done
            State_ReadData+8: begin
                clkOut <= 0;
                dataInCounter <= dataInCounter-1;
                
                // Check if we need to ACK a byte
                if (dataInCounter === 8) begin
                    delay <= I2CQuarterCycleDelay;
                    state <= State_ACK;
                    ack <= 1; // Tell State_ACK to issue an ACK
                    nextState <= State_ReadData+5; // Tell State_ACK to go to State_ReadData+5 after the ACK
                
                // Check if we're done shifting
                end else if (!dataInCounter) begin
                    delay <= I2CQuarterCycleDelay;
                    state <= State_ACK;
                    ack <= 0; // Tell State_ACK to issue a NACK
                    nextState <= State_StopOK; // Tell State_ACK to go to State_StopOK after the NACK
                
                // Otherwise continue shifting
                end else begin
                    delay <= I2CQuarterCycleDelay;
                    state <= State_ReadData+5;
                end
            end
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            // Issue ACK (SDA=0),
            // Delay 1/4 cycle
            State_ACK: begin
                dataOutShiftReg <= (ack ? 0 : ~0);
                delay <= I2CQuarterCycleDelay;
                state <= State_ACK+1;
            end
            
            // SCL=1,
            // Delay 1/4 cycle,
            State_ACK+1: begin
                clkOut <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= State_ACK+2;
            end
            
            // Delay 1/4 cycle,
            State_ACK+2: begin
                delay <= I2CQuarterCycleDelay;
                state <= State_ACK+3;
            end
            
            // SCL=0,
            // Delay 1/4 cycle
            State_ACK+3: begin
                clkOut <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= nextState;
            end
            
            
            
            
            
            
            
            
            
            
            
            
            // SDA=0,
            // Delay 1/4 cycle
            State_StopOK: begin
                status_err <= 0;
                dataOutShiftReg <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= State_Stop;
            end
            
            // SDA=0,
            // Delay 1/4 cycle
            State_StopFail: begin
                status_err <= 1;
                dataOutShiftReg <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= State_Stop;
            end
            
            // SCL=1,
            // Delay 1/4 cycle
            State_Stop: begin
                clkOut <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= State_Stop+1;
            end
            
            // Issue stop condition (SDA=0->1 while SCL=1),
            // Delay 1/4 cycle
            State_Stop+1: begin
                dataOutShiftReg <= ~0;
                delay <= I2CQuarterCycleDelay;
                state <= State_Stop+2;
            end
            
            // Tell client we're done
            State_Stop+2: begin
                // `Finish;
                status_done <= !status_done;
                state <= State_Idle;
            end
            endcase
        end
    end
endmodule

`endif

`timescale 1ns/1ps
`include "../ClockGen.v"

// TODO: communicate no ACK from slave to client (output that indicates success/failure?)
module PIXI2CMaster #(
    parameter ClkFreq = 12000000,   // `clk` frequency
    parameter I2CClkFreq = 400000   // `i2c_clk` frequency
)(
    input wire          clk,
    
    // Command port
    input wire[6:0]     cmd_slaveAddr,
    input wire          cmd_write,
    input wire[15:0]    cmd_regAddr,
    input wire[15:0]    cmd_writeData,
    output wire[15:0]   cmd_readData,
    input wire[1:0]     cmd_dataLen, // 0 (no command), 1 (1 byte), 2 (2 bytes)
    output reg          cmd_done = 0,
    output reg          cmd_ok = 0,
    
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
    
    
    
    
    
    reg[7:0] state = 0;
    reg[7:0] nextState = 0;
    reg ack = 0;
    reg[8:0] dataOutShiftReg = 0; // Low bit is sentinel
    wire dataOut = dataOutShiftReg[8];
    reg[16:0] dataInShiftReg = 0; // Low bit is sentinel
    assign cmd_readData = dataInShiftReg[15:0];
    wire dataIn;
    reg[DelayWidth-1:0] delay = 0;
    
    `ifdef SIM
        assign i2c_data = (!dataOut ? 0 : 1'bz);
        assign dataIn = i2c_data;
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
    localparam StateACK = 120;
    localparam StateStopOK = 140;
    localparam StateStopFail = 160;
    localparam StateStop = 180;
    always @(posedge clk) begin
        if (delay) begin
            delay <= delay-1;
        
        end else begin
            case (state)
            
            // Idle (SDA=1, SCL=1)
            StateIdle: begin
                i2c_clk <= 1;
                dataOutShiftReg <= ~0;
                delay <= I2CQuarterCycleDelay;
                state <= StateStart;
            end
            
            
            
            
            
            
            
            
            
            // Accept command,
            // Issue start condition (SDA=1->0 while SCL=1),
            // Delay 1/4 cycle
            StateStart: begin
                if (cmd_dataLen) begin
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
            // *** Note that dir=1 (write) on the initial transmission, even when reading.
            // *** If we intent to read, we perform a second START condition after
            // *** providing the slave address, and then provide the slave address/direction
            // *** again. This second time is when provide dir=1 (read).
            // *** See i2c docs for more information on how reads are performed.
            StateStart+2: begin
                dataOutShiftReg <= {cmd_slaveAddr, 1'b0 /* dir=0 (write, see comment above) */, 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                nextState <= StateRegAddr;
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
            
            // Check for ACK (SDA=0) or NACK (SDA=1),
            // Delay 1/4 cycle
            StateShiftOut+5: begin
                delay <= I2CQuarterCycleDelay;
                state <= (!dataIn ? StateShiftOut+6 : StateShiftOut+7);
            end
            
            // Handle ACK:
            // SCL=0,
            // Delay 1/4 cycle,
            // Go to `nextState`
            StateShiftOut+6: begin
                i2c_clk <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= nextState;
            end
            
            // Handle NACK:
            // SCL=0,
            // Delay 1/4 cycle,
            // Go to StateStop
            StateShiftOut+7: begin
                i2c_clk <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateStopFail;
            end
            
            
            
            
            
            
            
            // Shift out high 8 bits of address
            StateRegAddr: begin
                dataOutShiftReg <= {cmd_regAddr[15:8], 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                nextState <= StateRegAddr+1;
            end
            
            // Shift out low 8 bits of address
            StateRegAddr+1: begin
                dataOutShiftReg <= {cmd_regAddr[7:0], 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                if (cmd_write) begin
                    nextState <= (cmd_dataLen==2 ? StateWriteData : StateWriteData+1);
                end else begin
                    nextState <= (cmd_dataLen==2 ? StateReadData : StateReadData+1);
                end
            end
            
            
            
            
            
            
            
            
            
            // Shift out high 8 bits of data
            StateWriteData: begin
                dataOutShiftReg <= {cmd_writeData[15:8], 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                nextState <= StateWriteData+1;
            end
            
            // Shift out low 8 bits of data
            StateWriteData+1: begin
                dataOutShiftReg <= {cmd_writeData[7:0], 1'b1};
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                nextState <= StateStopOK;
            end
            
            
            
            
            
            
            
            
            
            
            
            // SDA=1,
            // Delay 1/4 cycle,
            StateReadData: begin
                dataOutShiftReg <= ~0;
                delay <= I2CQuarterCycleDelay;
                state <= StateReadData+1;
            end
            
            // SCL=1,
            // Delay 1/4 cycle
            StateReadData+1: begin
                i2c_clk <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= StateReadData+2;
            end
            
            // Issue repeated start condition (SDA=1->0 while SCL=1),
            // Delay 1/4 cycle
            StateReadData+2: begin
                dataOutShiftReg <= 0; // Start condition
                delay <= I2CQuarterCycleDelay;
                state <= StateReadData+3;
            end
            
            // SCL=0,
            // Delay 1/4 cycle
            StateReadData+3: begin
                i2c_clk <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateReadData+4;
            end
            
            // Shift out the slave address and direction (read), again.
            // The only difference is this time we actually specify the read direction,
            // whereas the first time we always specify the write direction. See comment
            // in the StateStart state for more info.
            StateReadData+4: begin
                dataOutShiftReg <= {cmd_slaveAddr, 1'b1 /* dir=1 (read) */, 1'b1};
                dataInShiftReg <= (cmd_dataLen==2 ? 1 : 1<<8); // Prepare dataInShiftReg with the sentinel
                delay <= I2CQuarterCycleDelay;
                state <= StateShiftOut;
                nextState <= StateReadData+5;
            end
            
            // SDA=1 (necessary since we return to this state after an ACK,
            //        so we need to relinquish SDA so the slave can control it),
            // Delay 1/4 cycle
            StateReadData+5: begin
                dataOutShiftReg <= ~0;
                delay <= I2CQuarterCycleDelay;
                state <= StateReadData+6;
            end
            
            // SCL=1,
            // Delay 1/4 cycle
            StateReadData+6: begin
                i2c_clk <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= StateReadData+7;
            end
            
            // Read another bit
            // Delay 1/4 cycle
            StateReadData+7: begin
                dataInShiftReg <= (dataInShiftReg<<1)|dataIn;
                delay <= I2CQuarterCycleDelay;
                state <= StateReadData+8;
            end
            
            // SCL=0,
            // Check if we need to ACK or if we're done
            StateReadData+8: begin
                i2c_clk <= 0;
                
                // Check if we need to ACK a byte
                if (dataInShiftReg[16:8] == 9'b0_00000001) begin
                    delay <= I2CQuarterCycleDelay;
                    state <= StateACK;
                    ack <= 1; // Tell StateACK to issue an ACK
                    nextState <= StateReadData+5; // Tell StateACK to go to StateReadData+5 after the ACK
                
                // Check if we're done shifting
                end else if (dataInShiftReg[16]) begin
                    delay <= I2CQuarterCycleDelay;
                    state <= StateACK;
                    ack <= 0; // Tell StateACK to issue a NACK
                    nextState <= StateStopOK; // Tell StateACK to go to StateStopOK after the NACK
                
                // Otherwise continue shifting
                end else begin
                    delay <= I2CQuarterCycleDelay;
                    state <= StateReadData+5;
                end
            end
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            // Issue ACK (SDA=0),
            // Delay 1/4 cycle
            StateACK: begin
                dataOutShiftReg <= (ack ? 0 : ~0);
                delay <= I2CQuarterCycleDelay;
                state <= StateACK+1;
            end
            
            // SCL=1,
            // Delay 1/4 cycle,
            StateACK+1: begin
                i2c_clk <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= StateACK+2;
            end
            
            // Delay 1/4 cycle,
            StateACK+2: begin
                delay <= I2CQuarterCycleDelay;
                state <= StateACK+3;
            end
            
            // SCL=0,
            // Delay 1/4 cycle
            StateACK+3: begin
                i2c_clk <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= nextState;
            end
            
            
            
            
            
            
            
            
            
            
            
            
            // SDA=0,
            // Delay 1/4 cycle
            StateStopOK: begin
                cmd_ok <= 1;
                dataOutShiftReg <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateStop;
            end
            
            // SDA=0,
            // Delay 1/4 cycle
            StateStopFail: begin
                cmd_ok <= 0;
                dataOutShiftReg <= 0;
                delay <= I2CQuarterCycleDelay;
                state <= StateStop;
            end
            
            // SCL=1,
            // Delay 1/4 cycle
            StateStop: begin
                i2c_clk <= 1;
                delay <= I2CQuarterCycleDelay;
                state <= StateStop+1;
            end
            
            // Issue stop condition (SDA=0->1 while SCL=1),
            // Delay 1/4 cycle
            StateStop+1: begin
                dataOutShiftReg <= ~0;
                delay <= I2CQuarterCycleDelay;
                state <= StateStop+2;
            end
            
            // Tell client we're done
            StateStop+2: begin
                cmd_done <= 1;
                state <= StateStop+3;
                // No delay! We only want cmd_done=1 for one cycle.
            end
            
            StateStop+3: begin
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
    
`ifdef SIM
    inout tri1          pix_sdata
`else
    inout wire          pix_sdata
`endif
);
    // ====================
    // Clock PLL (54.750 MHz)
    // ====================
    localparam ClkFreq = 54750000;
    wire clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(72),
        .DIVQ(4),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    
    
    
    // ====================
    // I2C Master
    // ====================
    reg[6:0]    cmd_slaveAddr = 0;
    reg         cmd_write = 0;
    reg[15:0]   cmd_regAddr = 0;
    reg[15:0]   cmd_writeData = 0;
    wire[15:0]  cmd_readData;
    reg[1:0]    cmd_dataLen = 0;
    wire        cmd_done;
    wire        cmd_ok;
    
    PIXI2CMaster #(
        .ClkFreq(ClkFreq),
        .I2CClkFreq(400000)
    
    ) pixI2CMaster(
        .clk(clk),
        
        .cmd_slaveAddr(cmd_slaveAddr),
        .cmd_write(cmd_write),
        .cmd_regAddr(cmd_regAddr),
        .cmd_writeData(cmd_writeData),
        .cmd_readData(cmd_readData),
        .cmd_dataLen(cmd_dataLen),
        .cmd_done(cmd_done),
        .cmd_ok(cmd_ok),
        
        .i2c_clk(pix_sclk),
        .i2c_data(pix_sdata)
    );
    
    
    
    
    
    // ====================
    // Main
    // ====================
    reg[3:0] state = 0;
    always @(posedge clk) begin
        case (state)
        
        // Write: 0x1234 = 0x5678
        0: begin
            cmd_slaveAddr <= 7'h42;
            cmd_write <= 1;
            cmd_regAddr <= 16'h1234;
            cmd_writeData <= 16'h5678;
            cmd_dataLen <= 2;
            
            state <= 1;
        end
        
        // Wait for the I2C transaction to complete
        1: begin
            if (cmd_done) begin
                $display("Write: %s\n", (cmd_ok ? "success" : "failed"));
                cmd_dataLen <= 0;
                state <= 2;
            end
        end
        
        // Read: 0x1234
        2: begin
            cmd_slaveAddr <= 7'h43;
            cmd_write <= 0;
            cmd_regAddr <= 16'habcd;
            cmd_dataLen <= 1;

            state <= 3;
        end

        // Wait for the I2C transaction to complete
        3: begin
            if (cmd_done) begin
                $display("Read: %s\n", (cmd_ok ? "success" : "failed"));
                // $display("READ DATA: 0x%x\n", (cmd_dataLen==1 ? cmd_readData[7:0] : cmd_readData));
                cmd_dataLen <= 0;
                state <= 0;
            end
        end
        
        endcase
    end
    
    
    
    
`ifdef SIM
    
    reg[7:0] dataIn = 0;
    reg[7:0] dataOut = 0;
    reg sdata = 1;
    assign pix_sdata = (!sdata ? 0 : 1'bz);
    
    reg[6:0] slaveAddr = 0;
    reg dir = 0;
    
    reg[15:0] regAddr = 0;
    reg[15:0] writeData = 0;
    reg[1:0] writeLen = 0;
    
    reg ack = 1;
    
    localparam I2CConditionNone = 0;
    localparam I2CConditionRestart = 1;
    localparam I2CConditionStop = 2;
    localparam I2CConditionNACK = 3;
    reg[1:0] i2cCondition = I2CConditionNone;
    wire i2cOK = (i2cCondition == I2CConditionNone);
    
    task ReadByte;
        reg[7:0] i;
        dataIn = 0;
        i2cCondition = I2CConditionNone;
        
        wait(!pix_sclk);
        for (i=0; i<8 && i2cOK; i++) begin
            reg sdataBefore;
            
            wait(pix_sclk);
            dataIn = (dataIn<<1)|pix_sdata;
            
            // Check for i2c condition (restart or stop)
            sdataBefore = pix_sdata;
            
            // Wait for SCL 1->0, or for SDA to change while SCL=1
            wait(!pix_sclk || pix_sdata!=sdataBefore);
            if (pix_sclk) begin
                if (pix_sdata) begin
                    // SDA=0->1 while SCL=1
                    i2cCondition = I2CConditionStop;
                end else begin
                    // SDA=1->0 while SCL=1
                    i2cCondition = I2CConditionRestart;
                end
            end
            
            wait(!pix_sclk);
        end
        
        if (i2cOK) begin
            // Send ACK
            wait(!pix_sclk);
            sdata = 0;
            ack = 0;
            wait(pix_sclk);
            wait(!pix_sclk);
            sdata = 1;
            ack = 1;
        end
    endtask
    
    task WriteByte;
        reg[7:0] i;
        for (i=0; i<8; i++) begin
            wait(!pix_sclk);
            // if (i==7) begin
            //     $finish;
            // end
            sdata = dataOut[7-i];
            wait(pix_sclk);
        end
        
        wait(!pix_sclk);
        sdata = 1;
        
        // Check for NACK
        wait(pix_sclk);
        if (pix_sdata) begin
            i2cCondition = I2CConditionNACK;
        end
        wait(!pix_sclk);
    endtask
    
    initial begin
        forever begin
            // Wait for idle condition (SDA=1 while SCL=1)
            wait(pix_sclk & pix_sdata);
            
            // Wait for start condition (SDA=1->0 while SCL=1)
            wait(pix_sclk & !pix_sdata);
            
            do begin
                ReadByte();
                if (i2cOK) begin
                    slaveAddr = dataIn[7:1];
                    dir = dataIn[0];
                    // $display("slave:0x%x dir:%d", slaveAddr, dir);
                end
                
                if (i2cOK) begin
                    // Read
                    if (dir) begin
                        $display("slave @ 0x%x", slaveAddr);
                        
                        dataOut = 8'hCA;
                        WriteByte();
                        
                        if (i2cOK) begin
                            dataOut = 8'hFE;
                            WriteByte();
                            $display("  READ: 0x%x (len=2)\n", regAddr);
                        end else begin
                            $display("  READ: 0x%x (len=1)\n", regAddr);
                        end
                    
                    // Write
                    end else begin
                        if (i2cOK) begin
                            ReadByte();
                            if (i2cOK) begin
                                regAddr[15:8] = dataIn;
                            end
                        end
                        
                        if (i2cOK) begin
                            ReadByte();
                            if (i2cOK) begin
                                regAddr[7:0] = dataIn;
                            end
                        end
                        
                        if (i2cOK) begin
                            ReadByte();
                            if (i2cOK) begin
                                writeData[7:0] = dataIn;
                                writeLen = 1;
                            end
                        end
                        
                        if (i2cOK) begin
                            ReadByte();
                            if (i2cOK) begin
                                writeData = (writeData<<8)|dataIn;
                                writeLen = 2;
                            end
                        end
                        
                        $display("slave @ 0x%x", slaveAddr);
                        if (writeLen == 1) begin
                            $display("  WRITE: 0x%x = 0x%x\n", regAddr, writeData[7:0]);
                        end else if (writeLen == 2) begin
                            $display("  WRITE: 0x%x = 0x%x\n", regAddr, writeData[15:0]);
                        end
                    end
                end
            end while (i2cCondition == I2CConditionRestart);
            
            // $finish;
        end
    end
    
    
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
        
        // Wait for ClockGen to start its clock
        wait(clk);
        
        #1000000;
        $finish;
    end
`endif

endmodule

module PixI2CMaster #(
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
    function [63:0] DivCeil;
        input [63:0] n;
        input [63:0] d;
        begin
            DivCeil = (n+d-1)/d;
        end
    endfunction
    
    // I2CQuarterCycleDelay: number of `clk` cycles for a quarter of the `i2c_clk` cycle to elapse.
    // DivCeil() is necessary to perform the quarter-cycle calculation, so that the
    // division is ceiled to the nearest clock cycle. (Ie -- slower than I2CClkFreq is OK, faster is not.)
    // -1 for the value that should be stored in a counter.
    localparam I2CQuarterCycleDelay = DivCeil(ClkFreq, 4*I2CClkFreq)-1;
    
    // Width of `delay`
    localparam DelayWidth = $clog2(I2CQuarterCycleDelay+1);
    
    
    
    
    
    reg[5:0] state = 0;
    reg[5:0] nextState = 0;
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
        SB_IO #(
            .PIN_TYPE(6'b1010_01)
        ) sdaTri (
            .PACKAGE_PIN(i2c_data),
            .OUTPUT_ENABLE(dataOut==0),
            .D_OUT_0(dataOut),
            .D_IN_0(dataIn)
        );
    `endif
    
    
    localparam StateIdle = 0;
    localparam StateStart = 1;
    localparam StateShiftOut = 4;
    localparam StateRegAddr = 12;
    localparam StateWriteData = 14;
    localparam StateReadData = 16;
    localparam StateACK = 25;
    localparam StateStopOK = 29;
    localparam StateStopFail = 30;
    localparam StateStop = 31;
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
            // *** If we intend to read, we perform a second START condition after
            // *** providing the slave address, and then provide the slave address/direction
            // *** again. This second time is when provide dir=1 (read).
            // *** See i2c docs for more information on how reads are performed.
            StateStart+2: begin
                dataOutShiftReg <= {cmd_slaveAddr, 1'b0 /* dir=0 (write, see comment above) */, 1'b1 /* sentinel */};
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
                dataOutShiftReg <= {cmd_slaveAddr, 1'b1 /* dir=1 (read) */, 1'b1  /* sentinel */};
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

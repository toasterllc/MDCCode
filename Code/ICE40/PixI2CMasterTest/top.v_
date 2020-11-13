`include "../Util/ClockGen.v"
`include "../Util/PixI2CMaster.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          clk24mhz,
    output reg[3:0]     led = 0,
    
    output wire         pix_sclk,
    
`ifdef SIM
    inout tri1          pix_sdata
`else
    inout wire          pix_sdata
`endif
);
    // ====================
    // Clock PLL (48 MHz)
    // ====================
    localparam ClkFreq = 48_000_000;
    wire clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(31),
        .DIVQ(4),
        .FILTER_RANGE(2)
    ) cg(.clkRef(clk24mhz), .clk(clk));
    
    
    
    
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
    
    PixI2CMaster #(
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
                if (cmd_ok) $display("Write: ✅\n");
                else        $display("Write: ❌\n");
                cmd_dataLen <= 0;
                state <= 2;
            end
        end
        
        // Read: 0x1234
        2: begin
            cmd_slaveAddr <= 7'h43;
            cmd_write <= 0;
            cmd_regAddr <= 16'habcd;
            cmd_dataLen <= 2;

            state <= 3;
        end
        
        // Wait for the I2C transaction to complete
        3: begin
            if (cmd_done) begin
                if (cmd_ok) $display("Read: ✅ (data: 0x%x)\n", (cmd_dataLen==1 ? cmd_readData[7:0] : cmd_readData));
                else $display("Read: ❌ (data: 0x%x)\n", (cmd_dataLen==1 ? cmd_readData[7:0] : cmd_readData));
                
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

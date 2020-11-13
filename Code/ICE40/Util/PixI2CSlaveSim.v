`ifndef PixI2CSlaveSim_v
`define PixI2CSlaveSim_v

module PixI2CSlaveSim(
    input wire i2c_clk,
    inout wire i2c_data
);
    
    reg[7:0] dataIn = 0;
    reg[7:0] dataOut = 0;
    reg sdata = 1;
    assign i2c_data = (!sdata ? 0 : 1'bz);
    
    reg[6:0] slaveAddr = 0;
    reg dir = 0;
    
    reg[15:0] regAddr = 0;
    reg[15:0] writeData = 0;
    reg[1:0] writeLen = 0;
    
    reg[15:0] mem[0:'hffff];
    
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
        
        wait(!i2c_clk);
        for (i=0; i<8 && i2cOK; i++) begin
            reg sdataBefore;
            
            $display("[PixI2CSlaveSim@0x%x] ReadByte %0d", slaveAddr, i);
            
            wait(i2c_clk);
            
            dataIn = (dataIn<<1)|i2c_data;
            
            // Check for i2c condition (restart or stop)
            sdataBefore = i2c_data;
            
            // Wait for SCL 1->0, or for SDA to change while SCL=1
            wait(!i2c_clk || i2c_data!=sdataBefore);
            
            $display("[PixI2CSlaveSim@0x%x] ReadByte %0d BBB", slaveAddr, i);
            
            if (i2c_clk) begin
                if (i2c_data) begin
                    // SDA=0->1 while SCL=1
                    i2cCondition = I2CConditionStop;
                end else begin
                    // SDA=1->0 while SCL=1
                    i2cCondition = I2CConditionRestart;
                end
            end
            
            wait(!i2c_clk);
            
            $display("[PixI2CSlaveSim@0x%x] ReadByte %0d CCC", slaveAddr, i);
        end
        
        if (i2cOK) begin
            // Send ACK
            wait(!i2c_clk);
            sdata = 0;
            ack = 0;
            wait(i2c_clk);
            wait(!i2c_clk);
            sdata = 1;
            ack = 1;
        end
    endtask
    
    task WriteByte;
        reg[7:0] i;
        for (i=0; i<8; i++) begin
            wait(!i2c_clk);
            sdata = dataOut[7-i];
            wait(i2c_clk);
        end
        
        wait(!i2c_clk);
        sdata = 1;
        
        // Check for NACK
        wait(i2c_clk);
        if (i2c_data) begin
            i2cCondition = I2CConditionNACK;
        end
        wait(!i2c_clk);
    endtask
    
    initial begin
        forever begin
            // Wait for idle condition (SDA=1 while SCL=1)
            wait(i2c_clk & i2c_data);
            
            // Wait for start condition (SDA=1->0 while SCL=1)
            wait(i2c_clk & !i2c_data);
            
            do begin
                ReadByte();
                if (i2cOK) begin
                    slaveAddr = dataIn[7:1];
                    dir = dataIn[0];
                    $display("[PixI2CSlaveSim@0x%x] dir:%d", slaveAddr, dir);
                end
                
                if (i2cOK) begin
                    // Read
                    if (dir) begin
                        dataOut = mem[regAddr][15:8];
                        WriteByte();
                        
                        if (i2cOK) begin
                            dataOut = mem[regAddr][7:0];
                            WriteByte();
                            $display("[PixI2CSlaveSim@0x%x] READ (len=2): mem[0x%x] = 0x%x", slaveAddr, regAddr, mem[regAddr][15:0]);
                        end else begin
                            $display("[PixI2CSlaveSim@0x%x] READ (len=1): mem[0x%x] = 0x%x", slaveAddr, regAddr, mem[regAddr][15:8]);
                        end
                    
                    // Write
                    end else begin
                        if (i2cOK) begin
                            // Reset writeLen so that we correctly handle the preparing-for-reading write transaction
                            writeLen = 0;
                            
                            ReadByte();
                            if (i2cOK) begin
                                regAddr[15:8] = dataIn;
                            end
                        end
                        
                        $display("[PixI2CSlaveSim@0x%x] AAA %b", slaveAddr, i2cOK);
                        if (i2cOK) begin
                            ReadByte();
                            if (i2cOK) begin
                                regAddr[7:0] = dataIn;
                            end
                        end
                        
                        $display("[PixI2CSlaveSim@0x%x] BBB %b", slaveAddr, i2cOK);
                        if (i2cOK) begin
                            ReadByte();
                            if (i2cOK) begin
                                writeData[7:0] = dataIn;
                                writeLen = 1;
                            end
                        end
                        
                        $display("[PixI2CSlaveSim@0x%x] CCC %b", slaveAddr, i2cOK);
                        if (i2cOK) begin
                            ReadByte();
                            if (i2cOK) begin
                                writeData = (writeData<<8)|dataIn;
                                writeLen = 2;
                            end
                        end
                        
                        $display("[PixI2CSlaveSim@0x%x] DDD %b", slaveAddr, i2cOK);
                        case (writeLen)
                        2: begin
                            $display("[PixI2CSlaveSim@0x%x] WRITE (len=2): mem[0x%x] = 0x%x", slaveAddr, regAddr, writeData[15:0]);
                            mem[regAddr] = writeData[15:0];
                        end
                        
                        1: begin
                            $display("[PixI2CSlaveSim@0x%x] WRITE (len=1): mem[0x%x] = 0x%x", slaveAddr, regAddr, writeData[7:0]);
                            mem[regAddr] = {mem[regAddr][15:8], writeData[7:0]};
                        end
                        
                        default: begin
                            // writeLen==0 is the case where we're reading, because i2c always starts reads with a
                            // write transaction to provide the slave address and register address
                        end
                        endcase
                    end
                end
            end while (i2cCondition == I2CConditionRestart);
        end
    end
endmodule

`endif

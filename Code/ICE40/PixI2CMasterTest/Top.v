`include "ClockGen.v"
`include "PixI2CMaster.v"
`include "TogglePulse.v"
`include "PixI2CSlaveSim.v"

`timescale 1ns/1ps

module Top(
    input wire  clk24mhz,
    output wire pix_sclk,
    inout tri1  pix_sdata
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
    reg         cmd_dataLen = 0;
    reg         cmd_trigger = 0;
    
    wire        status_done;
    wire[15:0]  status_readData;
    wire        status_err;
    
    `TogglePulse(done, status_done, posedge, clk);
    
    PixI2CMaster #(
        .ClkFreq(ClkFreq),
        .I2CClkFreq(400000)
    
    ) PixI2CMaster(
        .clk(clk),
        
        .cmd_slaveAddr(cmd_slaveAddr),
        .cmd_write(cmd_write),
        .cmd_regAddr(cmd_regAddr),
        .cmd_writeData(cmd_writeData),
        .cmd_dataLen(cmd_dataLen),
        .cmd_trigger(cmd_trigger), // Toggle
        
        .status_done(status_done), // Toggle
        .status_err(status_err),
        .status_readData(status_readData),
        
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
            cmd_dataLen <= 1; // 2 Bytes
            cmd_trigger <= !cmd_trigger;
            
            state <= 1;
        end
        
        // Wait for the I2C transaction to complete
        1: begin
            if (done) begin
                if (!status_err)    $display("Write: ✅\n");
                else                $display("Write: ❌\n");
                state <= 2;
            end
        end
        
        // Read: 0x1234
        2: begin
            cmd_slaveAddr <= 7'h43;
            cmd_write <= 0;
            cmd_regAddr <= 16'habcd;
            cmd_dataLen <= 1; // 2 Bytes
            cmd_trigger <= !cmd_trigger;
            
            state <= 3;
        end
        
        // Wait for the I2C transaction to complete
        3: begin
            if (done) begin
                if (!status_err) $display("Read: ✅ (data: 0x%x)\n", (cmd_dataLen ? status_readData : status_readData[7:0]));
                else $display("Read: ❌ (data: 0x%x)\n", (cmd_dataLen ? status_readData : status_readData[7:0]));
                state <= 0;
            end
        end
        
        endcase
    end
    
    PixI2CSlaveSim PixI2CSlaveSim(
        .i2c_clk(pix_sclk),
        .i2c_data(pix_sdata)
    );
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Top);
    end
endmodule

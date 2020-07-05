`timescale 1ns/1ps
`include "../ClockGen.v"

module I2CMaster #(
    parameter ClkFreq = 12000000,   // `clk` frequency
    parameter I2CClkFreq = 400000   // `i2c_clk` frequency
)(
    input wire          clk,
    
    // Command port
    input wire          cmd_trigger,
    input wire[6:0]     cmd_addr,
    input wire          cmd_write,
    input wire[7:0]     cmd_writeData,
    output reg[7:0]     cmd_readData,
    output reg          cmd_done = 0,
    
    // i2c port
    output reg          i2c_clk = 0,
    inout wire          i2c_data
);
    // Clocks() returns the number of clock cycles required for >= `t` nanoseconds to elapse.
    // `sub` is subtracted from that value, with the result clipped to zero.
    function [63:0] Clocks;
        input [63:0] t;
        input [63:0] sub;
        
        localparam NSecPerSec = 1000000000;
        begin
            Clocks = (t*ClkFreq+NSecPerSec-1)/NSecPerSec;
            if (Clocks >= sub) Clocks = Clocks-sub;
            else Clocks = 0;
        end
    endfunction
    
    function [63:0] Sub;
        input [63:0] a;
        input [63:0] b;
        begin
            if (a >= b) Sub = a-b;
            else Sub = 0;
        end
    endfunction
    
    // Number of `clk` cycles for half of the `i2c_clk` cycle.
    // In other words, this is how often we need to toggle `i2c_clk`.
    localparam I2CHalfCycleClocks = Clocks(I2CClkFreq/2, 0);
    
    // Width of `delay`
    localparam DelayWidth = $clog2(I2CHalfCycleClocks+1);
    
    
    
    
    
    reg[1:0] state = 0;
    reg i2c_dataOut = 0;
    wire i2c_dataIn;
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
            .D_OUT_0(i2c_dataOut),
            .D_IN_0(i2c_dataIn)
        );
    `endif
    
    always @(posedge clk) begin
        case (state)
        // Idle
        0: begin
            i2c_clk <= 1;
            i2c_dataOut <= 1;
            
            state <= 1;
        end
        
        // Accept command
        1: begin
            if (cmd_trigger) begin
                // Start condition
                i2c_dataOut <= 0;
            end
        end
        endcase
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

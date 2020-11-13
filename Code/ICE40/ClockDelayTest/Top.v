`include "../Util/ClockGen.v"
`include "../Util/Util.v"
`include "../Util/VariableDelay.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output wire clk,
    output wire clkDelayed,
    output reg[3:0] led = 0
);
    // ====================
    // Fast Clock (120 MHz)
    // ====================
    localparam FastClkFreq = 120_000_000;
    ClockGen #(
        .FREQ(FastClkFreq),
        .DIVR(0),
        .DIVF(39),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_fastClk(.clkRef(clk24mhz), .clk(clk));
    
    // // ====================
    // // Fast Clock (48 MHz)
    // // ====================
    // localparam FastClkFreq = 48_000_000;
    // ClockGen #(
    //     .FREQ(FastClkFreq),
    //     .DIVR(0),
    //     .DIVF(31),
    //     .DIVQ(4),
    //     .FILTER_RANGE(2)
    // ) ClockGen_fastClk(.clkRef(clk24mhz), .clk(clk));
    
    // ====================
    // Slow Clock (1 Hz)
    // ====================
`ifdef SIM
    localparam SlowClkFreq = 4000000;
`else
    localparam SlowClkFreq = 1;
`endif
    localparam SlowClkDividerWidth = $clog2(DivCeil(32'd24_000_000, SlowClkFreq));
    reg[SlowClkDividerWidth-1:0] slowClkDivider = 0;
    wire slowClk = slowClkDivider[SlowClkDividerWidth-1];
    always @(posedge clk24mhz) begin
        slowClkDivider <= slowClkDivider+1;
    end
    
    
    // // One-hot `sel`
    // localparam DelayCount = 10;
    // reg[DelayCount-1:0] sel = 0;
    // reg selInit = 0;
    // always @(posedge slowClk) begin
    //     led[0] <= !led[0];
    //     sel <= sel<<1|sel[$size(sel)-1]|!selInit;
    //     selInit <= 1;
    // end
    //
    // VariableDelay #(
    //     .Count(DelayCount)
    // ) VariableDelay(
    //     .in(clk),
    //     .sel(sel),
    //     .out(clkDelayed)
    // );
    
    // Binary `sel`
    localparam DelayCount = 16;
    reg[$clog2(DelayCount)-1:0] sel = 0;
    always @(posedge slowClk) begin
        led[0] <= !led[0];
        sel <= sel+1;
    end
    
    VariableDelay #(
        .Count(DelayCount)
    ) VariableDelay(
        .in(clk),
        .sel(sel),
        .out(clkDelayed)
    );
endmodule


`ifdef SIM
module Testbench();
    reg clk24mhz;
    wire clk;
    wire clkDelayed;
    wire[3:0] led;
    
    Top Top(.*);
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
    
    initial begin
        #10000;
        `Finish;
    end
    
    initial begin
        forever begin
            clk24mhz = 0;
            #21;
            clk24mhz = 1;
            #21;
        end
    end
endmodule
`endif

`include "../ClockGen.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    output wire[3:0]    led /* synthesis syn_keep=1 */
);
    // // ====================
    // // Clock PLL (100.5 MHz)
    // // ====================
    // localparam ClkFreq = 100500000;
    // wire pllClk;
    // ClockGen #(
    //     .FREQ(ClkFreq),
    //     .DIVR(0),
    //     .DIVF(66),
    //     .DIVQ(3),
    //     .FILTER_RANGE(1)
    // ) cg(.clk12mhz(clk12mhz), .clk(pllClk));
    
    // // ====================
    // // Clock PLL (91.5 MHz)
    // // ====================
    // localparam ClkFreq = 91500000;
    // wire pllClk;
    // ClockGen #(
    //     .FREQ(ClkFreq),
    //     .DIVR(0),
    //     .DIVF(60),
    //     .DIVQ(3),
    //     .FILTER_RANGE(1)
    // ) cg(.clk12mhz(clk12mhz), .clk(pllClk));
    
    // ====================
    // Clock PLL (81 MHz)
    // ====================
    localparam ClkFreq = 81000000;
    wire clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    
    reg[3:0] ledreg = 0;
    
    always @(posedge clk) begin
        ledreg <= ledreg+1;
    end
    
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
            .NEG_TRIGGER(1'b1)
        ) sbio (
            .PACKAGE_PIN(led[i]),
            .OUTPUT_ENABLE(1'b1),
            .D_OUT_0(ledreg[i]),
            .D_IN_0(),
            .OUTPUT_CLK(clk)
        );
    end
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        #10000;
        $finish;
    end
`endif
endmodule

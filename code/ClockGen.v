`timescale 1ns/1ps

module ClockGen #(
    // 100MHz by default
    parameter FREQ=100000000,
    parameter DIVR=0,
    parameter DIVF=66,
    parameter DIVQ=3,
    parameter FILTER_RANGE=1
)(
    input wire clk12mhz,
    output wire clk,
    output wire rst
);
    wire locked;
    wire pllclk;
    assign clk = pllclk&locked;
    
`ifdef SIM
    reg simClk;
    reg[3:0] simLockedCounter;
    assign pllclk = simClk;
    assign locked = &simLockedCounter;
    
    initial begin
        simClk = 0;
        simLockedCounter = 0;
        forever begin
            #((1000000000/FREQ)/2);
            simClk = !simClk;
            
            if (!simClk & !locked) begin
                simLockedCounter = simLockedCounter+1;
            end
        end
    end

`else
    SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(DIVR),
		.DIVF(DIVF),
		.DIVQ(DIVQ),
		.FILTER_RANGE(FILTER_RANGE)
    ) uut (
		.LOCK(locked),
		.RESETB(1'b1),
		.BYPASS(1'b0),
		.REFERENCECLK(clk12mhz),
		.PLLOUTCORE(pllclk)
    );
`endif
    
    // Generate `rst`
    reg[15:0] rst_;
    assign rst = !rst_[$size(rst_)-1];
    always @(posedge clk)
        if (!locked) rst_ <= 1;
        else if (rst) rst_ <= rst_<<1;
    
    // TODO: should we only output clk if locked==1? that way, if clients receive a clock, they know it's stable?
    
    // // Generate `rst`
    // reg[15:0] rstCounter;
    // always @(posedge clk)
    //     if (!locked) rstCounter <= 0;
    //     else if (rst) rstCounter <= rstCounter+1;
    // assign rst = !(&rstCounter);
endmodule

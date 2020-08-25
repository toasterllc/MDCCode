`include "Util.v"
`include "CRC7.v"
`include "ClockGen.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

module SDCardController(
    input wire          clk12mhz,
    
    
    
    // SDIO port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
);
    // ====================
    // Clock (120 MHz)
    // ====================
    wire clk;
    ClockGen #(
        .FREQ(120000000),
		.DIVR(0),
		.DIVF(79),
		.DIVQ(3),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst());
    
    
    
    
    
    // ====================
    // Pin: sd_clk
    // ====================
    assign sd_clk = clk;
    
    // ====================
    // Pin: sd_cmd
    // ====================
    wire sd_cmdIn;
    reg sd_cmdOut = 0;
    reg sd_cmdOutActive = 0;
    SB_IO #(
        .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
        .NEG_TRIGGER(1'b1)
    ) sbio (
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_CLK(clk),
        .OUTPUT_ENABLE(sd_cmdOutActive),
        .D_OUT_0(sd_cmdOut),
        .D_IN_0(sd_cmdIn)
    );
    
    // ====================
    // Pin: sd_dat
    // ====================
    wire[3:0] sd_datIn;
    reg[3:0] sd_datOut = 0;
    reg sd_datOutActive = 0;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
            .NEG_TRIGGER(1'b1)
        ) sbio (
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_CLK(clk),
            .OUTPUT_ENABLE(sd_datOutActive),
            .D_OUT_0(sd_datOut[i]),
            .D_IN_0(sd_datIn[i])
        );
    end
    
    
    
    
    
    // // ====================
    // // SD Card Initializer
    // // ====================
    // wire init_done;
    // wire init_sd_clk;
    // wire init_sd_cmdIn = sd_cmdIn;
    // wire init_sd_cmdOut;
    // wire init_sd_cmdOutActive;
    // wire[3:0] init_sd_dat = sd_datIn;
    // SDCardInitializer sdinit(
    //     .clk12mhz(clk12mhz),
    //     .done(init_done),
    //
    //     .sd_clk(init_sd_clk),
    //     .sd_cmdIn(init_sd_cmdIn),
    //     .sd_cmdOut(init_sd_cmdOut),
    //     .sd_cmdOutActive(init_sd_cmdOutActive),
    //     .sd_dat(init_sd_dat)
    // );
    //
    //
    //
    //
    //
    // // ====================
    // // `initDone` synchronizer
    // // ====================
    // reg initDone=0, initDoneTmp=0;
    // always @(negedge clk)
    //     {initDone, initDoneTmp} <= {initDoneTmp, init_done};
    
    
    
    
    
    
    
    // ====================
    // State Machine
    // ====================
    always @(posedge clk) begin
        sd_cmdOutActive <= 1;
        sd_cmdOut <= !sd_cmdOut;
    end
endmodule

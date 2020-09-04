// TODO: we may want to add support for partial reads, so we don't have to read a full block if the client only wants a few bytes

module SDCardController(
    input wire          clk12mhz,
    output wire         clk,    // FIXME: remove once we've set up our glue across our internal vs external clock domains
    
    // Command port
    input wire          cmd_trigger,
    output wire         cmd_accepted,
    input wire          cmd_write,
    input wire[22:0]    cmd_writeLen,
    input wire[31:0]    cmd_addr,
    
    // Data-in port
    input wire[15:0]    dataIn,
    output wire         dataIn_accepted,
    
    // Data-out port
    output wire[15:0]   dataOut,
    output wire         dataOut_valid,
    
    // Error port
    output wire         err,
    
    // SDIO port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
);
    // ====================
    // 180 MHz Clock PLL
    // ====================
    // wire clk;   // FIXME: uncomment when we remove the `clk` output port
    ClockGen #(
        .FREQ(180000000),
		.DIVR(0),
		.DIVF(59),
		.DIVQ(2),
		.FILTER_RANGE(1)
    ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    
    
    // ====================
    // Pin: sd_clk
    // ====================
    // Synchronize `sd_init_done` into `clk` domain
    reg initDone=0, initDoneTmp=0;
    always @(negedge clk)
        {initDone, initDoneTmp} <= {initDoneTmp, sd_init_done};
    assign sd_clk = (initDone ? clk : sd_init_clk);
    
    // ====================
    // Pin: sd_cmd
    // ====================
    wire sd_cmdIn;
    wire sd_cmdOut;
    wire sd_cmdOutActive;
    SB_IO #(
        .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
        .NEG_TRIGGER(1'b1)
    ) SB_IO (
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
    wire[3:0] sd_datOut;
    wire sd_datOutActive;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
            .NEG_TRIGGER(1'b1)
        ) SB_IO (
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_CLK(clk),
            .OUTPUT_ENABLE(sd_datOutActive),
            .D_OUT_0(sd_datOut[i]),
            .D_IN_0(sd_datIn[i])
        );
    end
    
    
    
    wire sd_init_done;
    wire sd_init_clk;
    wire sd_init_cmdIn = sd_cmdIn;
    wire sd_init_cmdOut;
    wire sd_init_cmdOutActive;
    wire[3:0] sd_init_datIn = sd_init_datIn;
    SDCardInitializer SDCardInitializer(
        .clk12mhz(clk12mhz),
        .done(sd_init_done),
        
        .sd_clk(sd_init_clk),
        .sd_cmdIn(sd_init_cmdIn),
        .sd_cmdOut(sd_init_cmdOut),
        .sd_cmdOutActive(sd_init_cmdOutActive),
        .sd_datIn(sd_init_datIn)
    );
    
    
    
    
    
    // SDCardControllerCore SDCardControllerCore(
    //     .clk(clk),
    //
    //     .cmd_trigger(cmd_trigger),
    //     .cmd_accepted(cmd_accepted),
    //     .cmd_write(cmd_write),
    //     .cmd_writeLen(cmd_writeLen),
    //     .cmd_addr(cmd_addr),
    //     .cmd_rca(16'b0), // FIXME: hook to up to SDCardInitializer output
    //
    //     .dataOut(dataOut),
    //     .dataOut_valid(dataOut_valid),
    //
    //     .dataIn(dataIn),
    //     .dataIn_accepted(dataIn_accepted),
    //
    //     .err(err),
    //
    //     .sd_cmdIn(sd_cmdIn),
    //     .sd_cmdOut(sd_cmdOut),
    //     .sd_cmdOutActive(sd_cmdOutActive),
    //     .sd_datIn(sd_datIn),
    //     .sd_datOut(sd_datOut),
    //     .sd_datOutActive(sd_datOutActive)
    // );
    
    
endmodule

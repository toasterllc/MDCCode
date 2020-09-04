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
    assign sd_clk = (initDone ? clk : init_sd_clk);
    
    // ====================
    // Pin: sd_cmd
    // ====================
    wire sd_cmdIn;
    wire sd_cmdOut = (initDone ? core_sd_cmdOut : init_sd_cmdOut);
    wire sd_cmdOutActive = (initDone ? core_sd_cmdOutActive : init_sd_cmdOutActive);
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
    wire[3:0] sd_datOut = core_sd_datOut;
    wire sd_datOutActive = core_sd_datOutActive;
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
    
    
    
    // ====================
    // SD Card Initializer
    // ====================
    wire init_done;
    wire[15:0] init_rca;
    wire init_sd_clk;
    wire init_sd_cmdIn = sd_cmdIn;
    wire init_sd_cmdOut;
    wire init_sd_cmdOutActive;
    wire[3:0] init_sd_datIn = sd_datIn;
    SDCardInitializer SDCardInitializer(
        .clk12mhz(clk12mhz),
        .rca(init_rca),
        .done(init_done),
        
        .sd_clk(init_sd_clk),
        .sd_cmdIn(init_sd_cmdIn),
        .sd_cmdOut(init_sd_cmdOut),
        .sd_cmdOutActive(init_sd_cmdOutActive),
        .sd_datIn(init_sd_datIn)
    );
    
    
    
    
    // ====================
    // SD Card Controller Core
    // ====================
    wire core_cmd_trigger = cmd_trigger && initDone;
    wire[15:0] core_rca = init_rca;
    wire core_sd_cmdIn = sd_cmdIn;
    wire core_sd_cmdOut;
    wire core_sd_cmdOutActive;
    wire[3:0] core_sd_datIn = sd_datIn;
    wire[3:0] core_sd_datOut;
    wire core_sd_datOutActive;
    SDCardControllerCore SDCardControllerCore(
        .clk(clk),
        .rca(core_rca),
        
        .cmd_trigger(core_cmd_trigger),
        .cmd_accepted(cmd_accepted),
        .cmd_write(cmd_write),
        .cmd_writeLen(cmd_writeLen),
        .cmd_addr(cmd_addr),
        
        .dataOut(dataOut),
        .dataOut_valid(dataOut_valid),
        
        .dataIn(dataIn),
        .dataIn_accepted(dataIn_accepted),
        
        .err(err),
        
        .sd_cmdIn(core_sd_cmdIn),
        .sd_cmdOut(core_sd_cmdOut),
        .sd_cmdOutActive(core_sd_cmdOutActive),
        .sd_datIn(core_sd_datIn),
        .sd_datOut(core_sd_datOut),
        .sd_datOutActive(core_sd_datOutActive)
    );
    
    
    
    
    
    // ====================
    // Logic
    // ====================
    // Synchronize `init_done` into `clk` domain
    reg initDone=0, initDoneTmp=0;
    always @(negedge clk)
        {initDone, initDoneTmp} <= {initDoneTmp, init_done};
    
    
endmodule

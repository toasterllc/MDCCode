`include "../Util.v"
`include "../ClockGen.v"
`include "../CRC7.v"
`include "../CRC16.v"
`include "../SDCardInitializer.v"

`ifdef SIM
`include "../SDCardSim.v"
`endif

`timescale 1ns/1ps

module Top(
`ifndef SIM
    input wire          clk12mhz    /* synthesis syn_keep=1 */,
    output wire         sd_clk      /* synthesis syn_keep=1 */,
    inout wire          sd_cmd      /* synthesis syn_keep=1 */,
    inout wire[3:0]     sd_dat      /* synthesis syn_keep=1 */,
    output wire[3:0]    led         /* synthesis syn_keep=1 */
`endif
);
    
`ifdef SIM
    reg         clk12mhz = 0;
    wire        sd_clk;
    tri1        sd_cmd;
    tri1[3:0]   sd_dat;
    wire[3:0]   led;
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        #100000000;
        `finish;
    end
    
    initial begin
        forever begin
            clk12mhz = 0;
            #42;
            clk12mhz = 1;
            #42;
        end
    end
    
    SDCardSim SDCardSim(
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
`endif
    
    
    
    // ====================
    // Pin: sd_clk
    // ====================
    assign sd_clk = init_sd_clk;
    
    // ====================
    // Pin: sd_cmd
    // ====================
    wire sd_cmdIn;
    wire sd_cmdOut = init_sd_cmdOut;
    wire sd_cmdOutActive = init_sd_cmdOutActive;
    `ifdef SIM
        assign sd_cmd = (sd_cmdOutActive ? sd_cmdOut : 1'bz);
        assign sd_cmdIn = sd_cmd;
    `else
        SB_IO #(
            .PIN_TYPE(6'b1010_01)
        ) SB_IO (
            .PACKAGE_PIN(sd_cmd),
            .OUTPUT_ENABLE(sd_cmdOutActive),
            .D_OUT_0(sd_cmdOut),
            .D_IN_0(sd_cmdIn)
        );
    `endif
    
    
    
    
    // ====================
    // Pin: sd_dat
    // ====================
    wire[3:0] sd_datIn;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        `ifdef SIM
            assign sd_dat[i] = 1'bz;
            assign sd_datIn[i] = sd_dat[i];
        `else
            SB_IO #(
                .PIN_TYPE(6'b1010_01)
            ) SB_IO (
                .PACKAGE_PIN(sd_dat[i]),
                .OUTPUT_ENABLE(0),
                .D_OUT_0(),
                .D_IN_0(sd_datIn[i])
            );
        `endif
    end
    
    
    
    // ====================
    // SD Card Initializer
    // ====================
    wire[15:0] init_rca;
    wire init_sd_clk;
    wire init_sd_cmdIn = sd_cmdIn;
    wire init_sd_cmdOut;
    wire init_sd_cmdOutActive;
    wire[3:0] init_sd_datIn = sd_datIn;
    SDCardInitializer SDCardInitializer(
        .clk12mhz(clk12mhz),
        .rca(init_rca),
        .done(),

        .sd_clk(init_sd_clk),
        .sd_cmdIn(init_sd_cmdIn),
        .sd_cmdOut(init_sd_cmdOut),
        .sd_cmdOutActive(init_sd_cmdOutActive),
        .sd_datIn(init_sd_datIn),
        
        .led(led)
    );
endmodule

`include "ClockGen.v"
`include "Util.v"

`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output reg[3:0] led = 0,
    output wire sd_clk = 0,
    inout wire sd_cmd,
    inout wire[3:0] sd_dat,
);
    // ====================
    // Slow Clock (375 kHz)
    // ====================
    reg[5:0] counter = 0;
    always @(posedge clk24mhz) begin
        counter <= counter+1;
    end
    wire slowClk = counter[$size(counter)-1];
    
    // // ====================
    // // Pin: sd_cmd
    // // ====================
    // SB_IO #(
    //     .PIN_TYPE(6'b1101_00)
    // ) SB_IO_sd_cmd (
    //     .INPUT_CLK(clk_int),
    //     .OUTPUT_CLK(clk_int),
    //     .PACKAGE_PIN(sd_cmd),
    //     .OUTPUT_ENABLE(cmd_active[0]),
    //     .D_OUT_0(cmdresp_shiftReg[47]),
    //     .D_IN_0(cmd_in)
    // );
    //
    // // ====================
    // // Pin: sd_dat[3:0]
    // // ====================
    // genvar i;
    // for (i=0; i<4; i=i+1) begin
    //     SB_IO #(
    //         .PIN_TYPE(6'b1101_00)
    //     ) SB_IO_sd_dat (
    //         .INPUT_CLK(clk_int),
    //         .OUTPUT_CLK(clk_int),
    //         .PACKAGE_PIN(sd_dat[i]),
    //         .OUTPUT_ENABLE(datOut_active[0]),
    //         .D_OUT_0(datOut_reg[16+i]),
    //         .D_IN_0(datIn[i])
    //     );
    // end
    
    // ====================
    // Slow Clock (375 kHz)
    // ====================
    reg[15:0] wideCounter = 0;
    always @(posedge clk24mhz) begin
        led <= `LeftBits(wideCounter, 0, 4);
        wideCounter <= wideCounter+1;
    end
    
    // // ====================
    // // Nets
    // // ====================
    // assign led[3:0] = {4{fastClk}};
    // assign sd_clk = fastClk;
    // assign sd_cmd = fastClk;
    // assign sd_dat[3:0] = {4{fastClk}};
endmodule

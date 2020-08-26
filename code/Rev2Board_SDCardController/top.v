`include "../SDCardController.v"

`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    output wire         sd_clk  /* synthesis syn_keep=1 */,
    inout wire          sd_cmd  /* synthesis syn_keep=1 */,
    inout wire[3:0]     sd_dat  /* synthesis syn_keep=1 */
);
    // ====================
    // SD Card Controller
    // ====================
    SDCardController sdcontroller(
        .clk(clk),
        
        .cmd_trigger(),
        .cmd_write(),
        .cmd_addr(),
        .cmd_len(),
        .cmd_dataOut(),
        .cmd_dataOutLen(),
        
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
`endif

`ifdef SIM
    initial begin
        #10000;
        $finish;
    end
`endif

endmodule

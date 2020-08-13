`include "../ClockGen.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps






module CRC7(
    input wire clk,
    input wire en,
    input din,
    output wire[6:0] dout
);
    reg[6:0] d = 0;
    wire dx = din ^ d[6];
    wire[6:0] dnext = { d[5], d[4], d[3], d[2] ^ dx, d[1], d[0], dx };
    assign dout = dnext;
    always @(posedge clk)
        d <= (!en ? 0 : dnext);
endmodule










module SDCardController #(
    parameter ClkFreq = 12000000,       // `clk` frequency
    parameter SDClkMaxFreq = 400000     // max `sd_clk` frequency
)(
    input wire          clk,
    
    // Command port
    input wire          cmd_trigger,
    input wire[5:0]     cmd_idx,
    input wire[31:0]    cmd_arg,
    output wire[135:0]  cmd_resp,
    output reg          cmd_done = 0,
    
    // SDIO port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
);
    function [63:0] DivCeil;
        input [63:0] n;
        input [63:0] d;
        begin
            DivCeil = (n+d-1)/d;
        end
    endfunction
    
    localparam SDClkDividerWidth = $clog2(DivCeil(ClkFreq, SDClkMaxFreq));
    reg[SDClkDividerWidth-1:0] sdClkDivider = 0;
    assign sd_clk = sdClkDivider[SDClkDividerWidth-1];

    always @(posedge clk) begin
        sdClkDivider <= sdClkDivider+1;
    end
    // assign sd_clk = clk;
    
    localparam CmdOutRegWidth = 40;
    reg[CmdOutRegWidth-1:0] cmdOutReg = 0;
    wire cmdOut = cmdOutReg[CmdOutRegWidth-1];
    reg cmdOutActive = 0;
    reg[5:0] cmdOutCounter = 0;
    wire cmdIn;
    
    wire[6:0] cmdCRC;
    CRC7 crc7(
        .clk(sd_clk),
        .en(cmdOutActive),
        .din(cmdOut),
        .dout(cmdCRC)
    );
    
    SB_IO #(
        .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
        // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
        .NEG_TRIGGER(1'b1)
    ) sbio (
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_ENABLE(cmdOutActive),
        .OUTPUT_CLK(sd_clk),
        .D_OUT_0(cmdOut),
        .D_IN_0(cmdIn)
    );
    
    reg[3:0] dataOut = 0;
    reg dataOutActive = 0;
    wire[3:0] dataIn;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
            // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
            .NEG_TRIGGER(1'b1)
        ) sbio (
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_ENABLE(dataOutActive),
            .OUTPUT_CLK(sd_clk),
            .D_OUT_0(dataOut[i]),
            .D_IN_0(dataIn[i])
        );
    end
    
    reg[5:0] state = 0;
    localparam StateInit = 0;   // +3
    localparam StateIdle = 4;
    
    always @(posedge sd_clk) begin
        cmdOutReg <= cmdOutReg<<1;
        cmdOutCounter <= cmdOutCounter-1;
        
        case (state)
        StateInit: begin
            cmdOutReg <= {2'b01, cmd_idx, cmd_arg};
            cmdOutCounter <= 40;
            cmdOutActive <= 1;
            state <= StateInit+1;
        end
        
        StateInit+1: begin
            if (cmdOutCounter == 1) begin
                // If this was the last bit, send the CRC, followed by the '1' end bit
                cmdOutReg <= {cmdCRC, 1'b1, 32'b0};
                cmdOutCounter <= 8;
                state <= StateInit+2;
            end
        end
        
        StateInit+2: begin
            if (cmdOutCounter == 1) begin
                // If this was the last bit, wrap up
                cmdOutActive <= 0;
                state <= StateIdle;
            end
        end
        
        StateIdle: begin
        end
        endcase
    end
    
endmodule








module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0 /* synthesis syn_keep=1 */,
    
    output wire         sd_clk  /* synthesis syn_keep=1 */,
    inout wire          sd_cmd  /* synthesis syn_keep=1 */,
    inout wire[3:0]     sd_dat  /* synthesis syn_keep=1 */
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
    
    
    // ====================
    // SD Card Controller
    // ====================
    SDCardController #(
        .ClkFreq(ClkFreq),
        .SDClkMaxFreq(400000)
    ) sdctrl(
        .clk(clk),
        
        .cmd_trigger(),
        .cmd_idx(6'b010001),
        .cmd_arg(32'b0),
        .cmd_resp(),
        .cmd_done(),
        
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        #1000000;
        $finish;
    end
`endif
    
endmodule

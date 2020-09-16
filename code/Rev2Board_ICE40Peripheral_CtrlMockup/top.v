`include "../Util.v"
`include "../ClockGen.v"
`include "../MsgChannel.v"
`include "../CRC7.v"
`include "../CRC16.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`ifdef SIM
`include "../SDCardSim.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    
    input wire          ctrl_clk,
    input wire          ctrl_di,
    output wire         ctrl_do,
    
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
    
    
    // ====================
    // Fast Clock (180 MHz)
    // ====================
    wire fastClk;
    ClockGen #(
        .FREQ(180000000),
        .DIVR(0),
        .DIVF(59),
        .DIVQ(2),
        .FILTER_RANGE(1)
    ) ClockGen(.clk12mhz(clk12mhz), .clk(fastClk));
    
    
    // ====================
    // Slow Clock (400 kHz)
    // ====================
    localparam SlowClkFreq = 400000;
    localparam SlowClkDividerWidth = $clog2(DivCeil(180000000, SlowClkFreq));
    reg[SlowClkDividerWidth-1:0] slowClkDivider = 0;
    wire slowClk = slowClkDivider[SlowClkDividerWidth-1];
    always @(posedge fastClk) begin
        slowClkDivider <= slowClkDivider+1;
    end
    
    
    
    // ====================
    // Pin: ctrl_di
    // ====================
    wire ctrlDI;
    SB_IO #(
        .PIN_TYPE(6'b0000_00)
    ) SB_IO_ctrl_clk (
        .INPUT_CLK(ctrl_clk),
        .PACKAGE_PIN(ctrl_di),
        .D_IN_0(ctrlDI)
    );
    
    
    
    // ====================
    // Pin: sd_clk
    // ====================
    reg sdClkSlow=0, sdClkSlowTmp=0;
    always @(negedge slowClk)
        {sdClkSlow, sdClkSlowTmp} <= {sdClkSlowTmp, ctrl_sdClkSlow};
    
    reg sdClkFast=0, sdClkFastTmp=0;
    always @(negedge fastClk)
        {sdClkFast, sdClkFastTmp} <= {sdClkFastTmp, ctrl_sdClkFast};
    
    assign sd_clk = (sdClkSlow ? slowClk : (sdClkFast ? fastClk : 0));
    
    
    
    
    // ====================
    // Registers
    // ====================
    reg[47:0] sd_cmdOutReg = 0;
    reg sd_cmdOutActive = 0;
    reg[5:0] sd_cmdOutCounter = 0;
    wire[6:0] sd_cmdOutCRC;
    reg sd_cmdOutCRCRst_ = 0;
    
    wire sd_cmdIn;
    reg[47:0] sd_cmdInReg = 0;
    reg sd_cmdInActive = 0;
    
    wire sd_msg_trigger;
    wire[47:0] sd_msg;
    
    reg[63:0] ctrl_cmdReg = 0;
    wire[3:0] ctrl_cmdCmd = ctrl_cmdReg[63:60];
    wire[59:0] ctrl_cmdArg = ctrl_cmdReg[59:0];
    reg ctrl_msg_trigger = 0;
    wire[47:0] ctrl_msg = ctrl_cmdArg[47:0];
    reg[6:0] ctrl_counter = 0;
    reg ctrl_sdClkSlow = 0;
    reg ctrl_sdClkFast = 0;
    
    
    
    // ====================
    // Pin: sd_cmd
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_sd_clk (
        .INPUT_CLK(sd_clk),
        .OUTPUT_CLK(sd_clk),
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_ENABLE(sd_cmdOutActive),
        .D_OUT_0(sd_cmdOutReg[47]),
        .D_IN_0(sd_cmdIn)
    );
    
    
    
    
    // ====================
    // CRC
    // ====================
    CRC7 CRC7_cmdOut(
        .clk(sd_clk),
        .rst_(sd_cmdOutCRCRst_),
        .din(sd_cmdOutReg[47]),
        .doutNext(sd_cmdOutCRC)
    );
    
    // ====================
    // SD State Machine
    // ====================
    
    MsgChannel #(
        .MsgLen(48)
    ) MsgChannel(
        .in_clk(ctrl_clk),
        .in_trigger(ctrl_msg_trigger),
        .in_msg(ctrl_msg),
        
        .out_clk(sd_clk),
        .out_trigger(sd_msg_trigger),
        .out_msg(sd_msg)
    );
    
    reg[1:0] sd_state = 0;
    always @(posedge sd_clk) begin
        sd_cmdOutReg <= sd_cmdOutReg<<1;
        sd_cmdOutCounter <= sd_cmdOutCounter-1;
        sd_cmdInReg <= (sd_cmdInReg<<1)|(sd_cmdInActive ? sd_cmdIn : 1'b1);
        
        case (sd_state)
        0: begin
            if (sd_msg_trigger) begin
                sd_cmdOutActive <= 1;
                sd_cmdOutReg <= sd_msg;
                sd_cmdOutCounter <= 47;
                sd_cmdOutCRCRst_ <= 1;
                sd_state <= 1;
            end
        end
        
        1: begin
            if (sd_cmdOutCounter === 8) begin
                sd_cmdOutReg[47:41] <= sd_cmdOutCRC;
            end
            
            if (!sd_cmdOutCounter) begin
                sd_cmdOutActive <= 0;
                sd_cmdOutCRCRst_ <= 0;
                sd_state <= 0;
            end
        end
        endcase
    end
    
    
    
    
    // ====================
    // Control State Machine
    // ====================
    reg[1:0] state = 0;
    always @(posedge ctrl_clk) begin
        if (ctrl_counter) begin
            ctrl_cmdReg <= (ctrl_cmdReg<<1)|ctrlDI;
            ctrl_counter <= ctrl_counter-1;
        end
        
        ctrl_msg_trigger <= 0; // Pulse
        
        case (state)
        0: begin
            if (!ctrlDI) begin
                ctrl_counter <= 64;
                state <= 1;
            end
        end
        
        1: begin
            if (!ctrl_counter) begin
                state <= 2;
            end
        end
        
        2: begin
            $display("[CTRL] Got command: %b [cmd: %0d, arg: %0d]", ctrl_cmdReg, ctrl_cmdCmd, ctrl_cmdArg);
            case (ctrl_cmdCmd)
            0: begin
                $display("[CTRL] Set SD clock source: %0d", ctrl_cmdArg[1:0]);
                ctrl_sdClkSlow <= ctrl_cmdArg[0];
                ctrl_sdClkFast <= ctrl_cmdArg[1];
            end
            
            1: begin
                $display("[CTRL] Clock out SD command: %0d", ctrl_msg);
                ctrl_msg_trigger <= 1;
            end
            endcase
            
            state <= 0;
        end
        endcase
    end
    
endmodule







`ifdef SIM
module Testbench();
    reg         clk12mhz;
    
    reg         ctrl_clk;
    reg         ctrl_di;
    wire        ctrl_do;
    
    wire        sd_clk;
    wire        sd_cmd;
    wire[3:0]   sd_dat;
    
    Top Top(.*);
    
    SDCardSim SDCardSim(
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Testbench);
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
    
    initial begin
        forever begin
            ctrl_clk = 0;
            #42;
            ctrl_clk = 1;
            #42;
        end
    end
    
    localparam CMD0 =   6'd0;      // GO_IDLE_STATE
    localparam CMD2 =   6'd2;      // ALL_SEND_CID
    localparam CMD3 =   6'd3;      // SEND_RELATIVE_ADDR
    localparam CMD6 =   6'd6;      // SWITCH_FUNC
    localparam CMD7 =   6'd7;      // SELECT_CARD/DESELECT_CARD
    localparam CMD8 =   6'd8;      // SEND_IF_COND
    localparam CMD11 =  6'd11;     // VOLTAGE_SWITCH
    localparam CMD41 =  6'd41;     // SD_SEND_OP_COND
    localparam CMD55 =  6'd55;     // APP_CMD
    
    initial begin
        reg[64:0] ctrl_diReg;
        reg[7:0] i;
        
        ctrl_di = 1;
        wait(ctrl_clk);
        wait(!ctrl_clk);
        
        ctrl_diReg = {1'b0, 4'd0, 60'b01};
        for (i=0; i<65; i++) begin
            ctrl_di = ctrl_diReg[64];
            ctrl_diReg = ctrl_diReg<<1;
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        ctrl_di = 1;
        for (i=0; i<5; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        ctrl_diReg = {1'b0, 4'd1, 12'b0, {2'b01, CMD0, 32'h00000000, 7'b0, 1'b1}};
        for (i=0; i<65; i++) begin
            ctrl_di = ctrl_diReg[64];
            ctrl_diReg = ctrl_diReg<<1;
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        ctrl_di = 1;
        for (i=0; i<5; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
    end
endmodule
`endif

`include "MsgChannel.v"

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

module SDCardController(
    input wire          clk12mhz,
    
    // Command port
    input wire          cmd_clk,
    input wire          cmd_trigger,
    input wire[37:0]    cmd_cmd,
    output wire[135:0]  cmd_resp,
    output wire         cmd_done,
    
    // SDIO port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
);
    // ====================
    // Internal clock (96 MHz)
    // ====================
    localparam PllClkFreq = 96000000;
    wire pllClk;
    ClockGen #(
        .FREQ(PllClkFreq),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(pllClk));
    
    function [63:0] DivCeil;
        input [63:0] n;
        input [63:0] d;
        begin
            DivCeil = (n+d-1)/d;
        end
    endfunction
    
    localparam ClkDividerWidth = $clog2(DivCeil(PllClkFreq, 400000));
    reg[ClkDividerWidth-1:0] clkDivider = 0;
    always @(posedge pllClk)
        clkDivider <= clkDivider+1;
    
    // wire int_clk = pllClk;
    wire int_clk = clkDivider[ClkDividerWidth-1];
    
    assign sd_clk = int_clk;
    
    // ====================
    // Synchronization
    //   {cmd_trigger, cmd_cmd} -> {int_trigger, int_cmd}
    // ====================
    wire int_trigger;
    wire[37:0] int_cmd;
    MsgChannel #(
        .MsgLen(38)
    ) cmdChannel(
        .in_clk(cmd_clk),
        .in_trigger(cmd_trigger),
        .in_msg(cmd_cmd),
        .out_clk(int_clk),
        .out_trigger(int_trigger),
        .out_msg(int_cmd)
    );
    
    // ====================
    // Synchronization
    //   {int_done, int_resp} -> {cmd_done, cmd_resp}
    // ====================
    reg int_done = 0;
    reg[135:0] int_resp = 0;
    reg int_respExpected = 0;
    MsgChannel #(
        .MsgLen(136)
    ) respChannel(
        .in_clk(int_clk),
        .in_trigger(int_done),
        .in_msg(int_resp),
        .out_clk(cmd_clk),
        .out_trigger(cmd_done),
        .out_msg(cmd_resp)
    );
    
    reg[39:0] int_cmdOutReg = 0;
    wire int_cmdOut = int_cmdOutReg[39];
    reg int_cmdOutActive = 0;
    wire int_cmdIn;
    reg[7:0] int_counter = 0;
    
    // ====================
    // `sd_cmd` IO Pin
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
        // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
        .NEG_TRIGGER(1'b1)
    ) sbio (
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_CLK(int_clk),
        .OUTPUT_ENABLE(int_cmdOutActive),
        .D_OUT_0(int_cmdOut),
        .D_IN_0(int_cmdIn)
    );
    
    // ====================
    // CRC
    // ====================
    wire[6:0] int_cmdCRC;
    CRC7 crc7(
        .clk(int_clk),
        .en(int_cmdOutActive),
        .din(int_cmdOut),
        .dout(int_cmdCRC)
    );
    
    // ====================
    // State Machine
    // ====================
    localparam StateIdle    = 0;   // +0
    localparam StateCmd     = 1;   // +1
    localparam StateResp    = 3;   // +1
    localparam StateDone    = 5;   // +0
    reg[5:0] int_state = 0;
    always @(posedge int_clk) begin
        int_cmdOutReg <= int_cmdOutReg<<1;
        int_counter <= int_counter-1;
        int_resp <= (int_resp<<1)|int_cmdIn;
        
        case (int_state)
        StateIdle: begin
            int_done <= 0; // Reset from previous state
            
            if (int_trigger) begin
                `ifdef SIM
                    $display("[SDCardController] Sending SD command: %b [ cmd: %0d, arg: 0x%x ]",
                        int_cmd,
                        int_cmd[37:32],     // command
                        int_cmd[31:0]       // arg
                    );
                `endif
                
                int_cmdOutReg <= {2'b01, int_cmd};
                int_cmdOutActive <= 1;
                int_respExpected <= |int_cmd[37:32];
                int_counter <= 40;
                int_state <= StateCmd;
            end
        end
        
        StateCmd: begin
            if (int_counter == 1) begin
                // If this was the last bit, send the CRC, followed by the '1' end bit
                int_cmdOutReg <= {int_cmdCRC, 1'b1, 32'b0};
                int_counter <= 8;
                int_state <= StateCmd+1;
            end
        end
        
        StateCmd+1: begin
            if (int_counter == 1) begin
                // If this was the last bit, wrap up
                int_cmdOutActive <= 0;
                int_state <= (int_respExpected ? StateResp : StateDone);
            end
        end
        
        StateResp: begin
            // Wait for the response to start
            if (!int_cmdIn) begin
                int_counter <= 135;
                int_state <= StateResp+1;
            end
        end
        
        StateResp+1: begin
            if (int_counter == 1) begin
                // If this was the last bit, wrap up
                int_state <= StateDone;
            end
        end
        
        StateDone: begin
            int_done <= 1;
            int_state <= StateIdle;
        end
        endcase
    end
    
    // function [63:0] DivCeil;
    //     input [63:0] n;
    //     input [63:0] d;
    //     begin
    //         DivCeil = (n+d-1)/d;
    //     end
    // endfunction
    //
    // localparam SDClkDividerWidth = $clog2(DivCeil(ClkFreq, SDClkMaxFreq));
    // reg[SDClkDividerWidth-1:0] sdClkDivider = 0;
    // assign sd_clk = sdClkDivider[SDClkDividerWidth-1];
    //
    // always @(posedge clk) begin
    //     sdClkDivider <= sdClkDivider+1;
    // end
    // assign sd_clk = clk;
    
    // reg[3:0] dataOut = 0;
    // reg dataOutActive = 0;
    // wire[3:0] dataIn;
    // genvar i;
    // for (i=0; i<4; i=i+1) begin
    //     SB_IO #(
    //         .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
    //         // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
    //         .NEG_TRIGGER(1'b1)
    //     ) sbio (
    //         .PACKAGE_PIN(sd_dat[i]),
    //         .OUTPUT_CLK(intClk),
    //         .OUTPUT_ENABLE(dataOutActive),
    //         .D_OUT_0(dataOut[i]),
    //         .D_IN_0(dataIn[i])
    //     );
    // end
    
endmodule

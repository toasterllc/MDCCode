`include "MsgChannel.v"

`define FITS(container, value) ($size(container) >= $clog2(value+64'b1));

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
    localparam ClkFreq = 96000000;
    wire int_clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(int_clk));
    
    function [63:0] DivCeil;
        input [63:0] n;
        input [63:0] d;
        begin
            DivCeil = (n+d-1)/d;
        end
    endfunction
    
    localparam OutClkSlowFreq = 400000;
    // OutClkSlowHalfCycleDelay: number of `int_clk` cycles for a half `sd_clk`
    // cycle to elapse. DivCeil() is necessary to perform the half-cycle
    // calculation, so that the division is ceiled to the nearest clock
    // cycle. (Ie -- slower than OutClkSlowFreq is OK, faster is not.)
    // -1 for the value that should be stored in a counter.
    localparam OutClkSlowHalfCycleDelay = DivCeil(ClkFreq, 2*OutClkSlowFreq)-1;
    
    reg int_outClkFastMode = 0;
    wire int_outClkFast = int_clk;
    reg int_outClkSlow = 0;
    wire int_outClk = (int_outClkFastMode ? int_outClkFast : int_outClkSlow);
    assign sd_clk = int_outClk;
    
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
    reg[7:0] int_delay = 0; // TODO: experiment with making this a free-running base-2 countdown -- should make our max speed faster
    
    Verify that `SDClkSlowHalfCycleDelay` fits in int_counter
    assert(`FITS(int_delay, SDClkSlowHalfCycleDelay));
    
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
    // `sd_dat` IO Pins
    // ====================
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
            // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
            .NEG_TRIGGER(1'b1)
        ) sbio (
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_CLK(int_clk),
            .OUTPUT_ENABLE(0),
            .D_OUT_0(),
            .D_IN_0()
        );
    end
    
    // ====================
    // CRC
    // ====================
    wire[6:0] int_cmdCRC;
    CRC7 crc7(
        .clk(int_outClk),
        .en(int_cmdOutActive),
        .din(int_cmdOut),
        .dout(int_cmdCRC)
    );
    
    // ====================
    // State Machine
    // ====================
    localparam StateInit_Init       = 0;   // +0
    localparam StateInit_CmdOut     = 0;   // +0
    localparam StateInit_CRCOut     = 0;   // +0
    
    localparam StateIdle    = 0;   // +0
    localparam StateCmd     = 1;   // +1
    localparam StateResp    = 3;   // +1
    
    localparam CMD0 =   0;      // GO_IDLE_STATE
    localparam CMD2 =   2;      // ALL_SEND_CID
    localparam CMD3 =   3;      // SEND_RELATIVE_ADDR
    localparam CMD6 =   6;      // SWITCH_FUNC
    localparam CMD7 =   7;      // SELECT_CARD/DESELECT_CARD
    localparam CMD8 =   8;      // SEND_IF_COND
    localparam CMD41 =  41;     // SD_SEND_OP_COND
    localparam CMD55 =  55;     // APP_CMD
    
    reg initDone = 0;
    reg[5:0] int_state = 0;
    reg[5:0] int_nextState = 0;
    always @(posedge int_clk) begin
        if (!initDone) begin
            if (int_delay) int_delay <= int_delay-1;
            else begin
                case (int_state)
                StateInit_Init: begin
                    int_cmdOutReg <= {2'b01, CMD0, 32'h00000000};
                    int_state <= StateInit_CmdOut;
                    int_nextState <= StateInit_Init+1;
                end
                
                StateInit_Init+1: begin
                    int_cmdOutReg <= {2'b01, CMD8, 32'h000001AA};
                    int_state <= StateInit_CmdOut;
                    int_nextState <= StateInit_Init+2;
                end
                
                StateInit_Init+2: begin
                    int_state <= StateInit_RespIn;
                    int_nextState <= StateInit_Init+3;
                end
                
                StateInit_Init+3: begin
                    
                end
                
                
                
                
                StateInit_CmdOut: begin
                    int_outClkSlow <= 0;
                    int_cmdOutActive <= 1;
                    int_counter <= 40;
                    int_delay <= SDClkSlowHalfCycleDelay;
                    int_state <= StateInit_CmdOut+1;
                end
                
                StateInit_CmdOut+1: begin
                    int_outClkSlow <= 1;
                    int_delay <= SDClkSlowHalfCycleDelay;
                    int_state <= StateInit_CmdOut+2;
                end
                
                StateInit_CmdOut+2: begin
                    int_outClkSlow <= 0;
                    
                    if (int_counter == 1) begin
                        int_state <= StateInit_CRCOut;
                    
                    end else begin
                        int_cmdOutReg <= int_cmdOutReg<<1;
                        int_counter <= int_counter-1;
                        int_delay <= SDClkSlowHalfCycleDelay;
                        int_state <= StateInit_CmdOut;
                    end
                end
                
                
                
                
                
                
                
                StateInit_CRCOut: begin
                    int_cmdOutReg <= {int_cmdCRC, 1'b1, 32'b0};
                    int_counter <= 8;
                    int_delay <= SDClkSlowHalfCycleDelay;
                    int_state <= StateInit_CRCOut+1;
                end
                
                StateInit_CRCOut+1: begin
                    int_outClkSlow <= 1;
                    int_delay <= SDClkSlowHalfCycleDelay;
                    int_state <= StateInit_CRCOut+2;
                end
                
                StateInit_CRCOut+2: begin
                    int_outClkSlow <= 0;
                    
                    if (int_counter == 1) begin
                        int_delay <= SDClkSlowHalfCycleDelay;
                        int_state <= int_nextState;
                    
                    end else begin
                        int_cmdOutReg <= int_cmdOutReg<<1;
                        int_counter <= int_counter-1;
                        int_delay <= SDClkSlowHalfCycleDelay;
                        int_state <= StateInit_CRCOut+1;
                    end
                end
                
                
                
                
                StateInit_RespIn: begin
                    int_outClkSlow <= 0;
                    int_cmdOutActive <= 0;
                    int_delay <= SDClkSlowHalfCycleDelay;
                    int_state <= StateInit_RespIn+1;
                end
                
                StateInit_RespIn+1: begin
                    
                end
                
                
                
                endcase
            end
        
        end else begin
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
                    if (int_respExpected) begin
                        int_state <= StateResp;
                    
                    end else begin
                        int_done <= 1;
                        int_state <= StateIdle;
                    end
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
                    int_done <= 1;
                    int_state <= StateIdle;
                end
            end
            endcase
        end
        
        
        case (int_initState)
        InitStateInit: begin
            int_cmdOutReg <= {2'b01, CMD0, 32'b0};
            int_cmdOutActive <= 1;
            int_initState <= InitStateInit+1;
        end
        
        InitStateShiftOut: begin
            if (int_delay) begin
                int_delay <= int_delay-1;
            
            end else begin
                int_outClkSlow <= !int_outClkSlow;
                int_cmdOutReg <= int_cmdOutReg<<1;
                
                int_cmdOutReg <= {2'b01, CMD0, 32'b0};
                int_cmdOutActive <= 1;
                int_initState <= InitStateInit+1;
            end
        end
        
        InitStateShiftOut: begin
            if (int_delay) begin
                int_delay <= int_delay-1;
            
            end else begin
                int_outClkSlow <= !int_outClkSlow;
                int_cmdOutReg <= int_cmdOutReg<<1;
                
                int_cmdOutReg <= {2'b01, CMD0, 32'b0};
                int_cmdOutActive <= 1;
                int_initState <= InitStateInit+1;
            end
        end
        
        InitStateDone: begin
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

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
    
    reg[39:0] int_cmdOutReg = 0;
    wire int_cmdOut = int_cmdOutReg[39];
    reg int_cmdOutActive = 0;
    wire int_cmdIn;
    reg[7:0] int_counter = 0;
    reg[7:0] int_delay = 0; // TODO: experiment with making this a free-running base-2 countdown -- should make our max speed faster
    
    // Verify that `OutClkSlowHalfCycleDelay` fits in int_counter
    // TODO:
    // assert(`FITS(int_delay, OutClkSlowHalfCycleDelay));
    
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
            .OUTPUT_ENABLE(1'b0),
            .D_OUT_0(),
            .D_IN_0()
        );
    end
    
    // ====================
    // CRC
    // ====================
    wire[6:0] int_cmdCRC;
    CRC7 cmdCRC(
        .clk(int_outClk),
        .en(int_cmdOutActive),
        .din(int_cmdOut),
        .dout(int_cmdCRC)
    );
    
    wire[6:0] int_respCRC;
    CRC7 respCRC(
        .clk(),
        .en(),
        .din(),
        .dout()
    );
    
    // ====================
    // State Machine
    // ====================
    localparam StateInit       = 0;   // +3
    localparam StateCmdOut     = 4;   // +2
    localparam StateRespIn     = 7;   // +3
    
    localparam CMD0 =   6'd0;      // GO_IDLE_STATE
    localparam CMD2 =   6'd2;      // ALL_SEND_CID
    localparam CMD3 =   6'd3;      // SEND_RELATIVE_ADDR
    localparam CMD6 =   6'd6;      // SWITCH_FUNC
    localparam CMD7 =   6'd7;      // SELECT_CARD/DESELECT_CARD
    localparam CMD8 =   6'd8;      // SEND_IF_COND
    localparam CMD41 =  6'd41;     // SD_SEND_OP_COND
    localparam CMD55 =  6'd55;     // APP_CMD
    
    reg[5:0] int_state = 0;
    reg[5:0] int_nextState = 0;
    reg[135:0] int_resp = 0;
    reg int_cmdOutNeedCRC = 0;
    always @(posedge int_clk) begin
        if (int_delay) int_delay <= int_delay-1;
        else begin
            case (int_state)
            StateInit: begin
                int_cmdOutReg <= {2'b01, CMD0, 32'h00000000};
                int_cmdOutNeedCRC <= 1;
                int_state <= StateCmdOut;
                int_nextState <= StateInit+1;
            end
            
            StateInit+1: begin
                int_cmdOutReg <= {2'b01, CMD8, 32'h000001AA};
                int_cmdOutNeedCRC <= 1;
                int_state <= StateCmdOut;
                int_nextState <= StateInit+2;
            end
            
            StateInit+2: begin
                int_state <= StateRespIn;
                int_nextState <= StateInit+3;
                int_counter <= 48;
            end
            
            
            
            
            StateCmdOut: begin
                int_outClkSlow <= 0;
                int_cmdOutActive <= 1;
                int_counter <= 40;
                int_delay <= OutClkSlowHalfCycleDelay;
                int_state <= StateCmdOut+1;
            end
            
            StateCmdOut+1: begin
                int_outClkSlow <= 1;
                int_delay <= OutClkSlowHalfCycleDelay;
                int_state <= StateCmdOut+2;
            end
            
            StateCmdOut+2: begin
                int_outClkSlow <= 0;
                
                if (int_counter != 1) begin
                    int_cmdOutReg <= int_cmdOutReg<<1;
                    int_counter <= int_counter-1;
                    int_delay <= OutClkSlowHalfCycleDelay;
                    int_state <= StateCmdOut+1;
                
                end else if (int_cmdOutNeedCRC) begin
                    int_cmdOutNeedCRC <= 0;
                    int_cmdOutReg <= {int_cmdCRC, 1'b1, 32'b0};
                    int_counter <= 8;
                    int_delay <= OutClkSlowHalfCycleDelay;
                    int_state <= StateCmdOut+1;
                
                end else begin
                    int_cmdOutActive <= 0;
                    int_state <= int_nextState;
                end
            end
            
            
            
            
            StateRespIn: begin
                int_outClkSlow <= 0;
                int_delay <= OutClkSlowHalfCycleDelay;
                int_state <= StateRespIn+1;
            end
            
            StateRespIn+1: begin
                int_outClkSlow <= 1;
                if (!int_cmdIn) begin
                    int_state <= StateRespIn+2;
                
                end else begin
                    int_delay <= OutClkSlowHalfCycleDelay;
                    int_state <= StateRespIn;
                end
            end
            
            StateRespIn+2: begin
                int_outClkSlow <= 1;
                int_resp <= (int_resp<<1)|int_cmdIn;
                
                if (int_counter != 1) begin
                    int_counter <= int_counter-1;
                    int_delay <= OutClkSlowHalfCycleDelay;
                    int_state <= StateRespIn+3;
                
                end else begin
                    int_delay <= OutClkSlowHalfCycleDelay;
                    int_state <= int_nextState;
                end
            end
            
            StateRespIn+3: begin
                int_outClkSlow <= 0;
                int_delay <= OutClkSlowHalfCycleDelay;
                int_state <= StateRespIn+2;
            end
            
            
            
            endcase
        end
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

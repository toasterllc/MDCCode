`define FITS(container, value) ($size(container) >= $clog2(value+64'b1));

module CRC7(
    input wire clk,
    input wire en,
    input din,
    output wire[6:0] dout,
    output wire[6:0] doutNext
);
    reg[6:0] d = 0;
    wire dx = din ^ d[6];
    wire[6:0] dnext = { d[5], d[4], d[3], d[2] ^ dx, d[1], d[0], dx };
    always @(posedge clk) begin
        // if (en) $display("CRC bit: %b", din);
        if (!en) d <= 0;
        else d <= dnext;
    end
    assign dout = d;
    assign doutNext = dnext;
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
    localparam Int_ClkFreq = 96000000;
    wire int_clk;
    ClockGen #(
        .FREQ(Int_ClkFreq),
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
    
    localparam Int_OutClk_SlowFreq = 400000;
    localparam Int_OutClk_DividerWidth = $clog2(DivCeil(Int_ClkFreq, Int_OutClk_SlowFreq));
    reg[Int_OutClk_DividerWidth-1:0] int_outClk_divider = 0;
    always @(posedge int_clk)
        int_outClk_divider <= int_outClk_divider+1;
    
    reg int_outClk_fastMode = 0;
    wire int_outClk_fast = int_clk;
    wire int_outClk_slow = int_outClk_divider[Int_OutClk_DividerWidth-1];
    reg int_outClk_slowLast = 0;
    wire int_outClk = (int_outClk_fastMode ? int_outClk_fast : int_outClk_slow);
    assign sd_clk = int_outClk;
    
    reg[47:0] int_cmdOutReg = 0;
    reg [7:0] int_cmdOutCounter = 0;
    wire int_cmdOut = int_cmdOutReg[47];
    reg int_cmdOutActive = 0;
    
    reg[135:0] int_cmdInReg = 0;
    reg [7:0] int_cmdInCounter = 0;
    wire int_cmdIn;
    reg int_cmdInActive = 0;
    
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
    wire[6:0] int_cmdOutCRC;
    reg int_cmdOutCRCEn = 0;
    CRC7 cmdOutCRC(
        .clk(int_outClk_slow),
        .en(int_cmdOutCRCEn),
        .din(int_cmdOut),
        .dout(int_cmdOutCRC)
    );
    
    wire[6:0] int_cmdInCRC;
    reg int_cmdInCRCEn = 0;
    CRC7 cmdInCRC(
        .clk(int_outClk_slow),
        .en(int_cmdInCRCEn),
        .din(int_cmdInReg[0]),
        .dout(int_cmdInCRC)
    );

    // ====================
    // State Machine
    // ====================
    localparam StateInit       = 0;   // +3
    localparam StateCmdOut     = 4;   // +0
    localparam StateRespIn     = 5;   // +1
    
    localparam CMD0 =   6'd0;      // GO_IDLE_STATE
    localparam CMD2 =   6'd2;      // ALL_SEND_CID
    localparam CMD3 =   6'd3;      // SEND_RELATIVE_ADDR
    localparam CMD6 =   6'd6;      // SWITCH_FUNC
    localparam CMD7 =   6'd7;      // SELECT_CARD/DESELECT_CARD
    localparam CMD8 =   6'd8;      // SEND_IF_COND
    localparam CMD41 =  6'd41;     // SD_SEND_OP_COND
    localparam CMD55 =  6'd55;     // APP_CMD
    
    // TODO: we should add dummy cycles between all our commands, just to be safe
    // TODO: there are certain commands that require dummy cycles at the end!
    
    // TODO: try using strategy where a counter automatically toggles int_outClkSlow
    
    // TODO: try switching to a single counter (int_counter), instead of cmdInCounter, cmdOutCounter
    
    // TODO: try getting rid of int_cmdOutCounter and just looking at a sentinel. in the past though this made things slower didnt it? also try using a separate shift register
    
    reg[5:0] int_state = 0;
    reg[5:0] int_nextState = 0;
    reg[6:0] int_respInExpectedCRC = 0;
    reg int_respCheckCRC = 0;
    always @(posedge int_clk) begin
        int_outClk_slowLast <= int_outClk_slow;
        
        // Posedge
        if (!int_outClk_slowLast && int_outClk_slow) begin
            int_cmdInReg <= (int_cmdInReg<<1)|int_cmdIn;
            if (int_cmdInActive) int_cmdInCounter <= int_cmdInCounter-1;
        end
        
        // Negedge
        if (int_outClk_slowLast && !int_outClk_slow) begin
            int_cmdOutReg <= int_cmdOutReg<<1;
            int_cmdOutCounter <= int_cmdOutCounter-1;
            
            case (int_state)
            StateInit: begin
                int_cmdOutReg <= {2'b01, CMD0, 32'h00000000, 7'b0, 1'b1};
                int_cmdOutCounter <= 47;
                int_cmdOutActive <= 1;
                int_cmdOutCRCEn <= 1;
                int_cmdInCounter <= 0;
                int_state <= StateCmdOut;
                int_nextState <= StateInit+1;
            end
            
            StateInit+1: begin
                int_cmdOutReg <= {2'b01, 6'd17, 32'h00000000, 7'b0, 1'b1};
                int_cmdOutCounter <= 47;
                int_cmdOutActive <= 1;
                int_cmdOutCRCEn <= 1;
                int_cmdInCounter <= 47;
                int_state <= StateCmdOut;
                int_nextState <= StateInit+2;
            end
            
            StateInit+2: begin
                // int_counter <= 47;
                // int_respCheckCRC <= 1;
                // int_state <= StateRespIn;
                // int_nextState <= StateInit+3;
            end
            
            StateInit+3: begin
            end
            
            StateCmdOut: begin
                if (int_cmdOutCRCEn && (int_cmdOutCounter==8)) begin
                    int_cmdOutReg[47:41] <= int_cmdOutCRC;
                
                end else if (!int_cmdOutCounter) begin
                    int_cmdOutActive <= 0;
                    int_cmdOutCRCEn <= 0;
                    int_state <= StateRespIn;
                end
            end
            
            // Wait for the response to start
            StateRespIn: begin
                if (!int_cmdInReg[0]) int_cmdInActive <= 1;
                if (!int_cmdInCounter) int_state <= StateRespIn+1;
            end
            
            StateRespIn+1: begin
                int_cmdInActive <= 0;
                int_state <= int_nextState;
                $display("Got response: %b", int_cmdInReg);
            end
            
            // // Wait for response to start
            // StateRespIn: begin
            //     // $display("AAA %b", int_cmdInReg);
            //     if (!int_cmdInReg[0]) begin
            //         int_cmdInActive <= 1;
            //         int_cmdInCRCEn <= 1;
            //         int_state <= StateRespIn+1;
            //     end
            // end
            //
            // // Check transmission bit
            // StateRespIn+1: begin
            //     // $display("AAA %b", int_cmdInReg);
            //     if (int_cmdInReg[0]) begin
            //         // TODO: handle bad response
            //         `ifdef SIM
            //             $display("Bad transmission bit");
            //         `endif
            //
            //     end else begin
            //         int_state <= StateRespIn+2;
            //     end
            // end
            //
            // StateRespIn+2: begin
            //     if (int_cmdInCounter == 7) begin
            //         int_respInExpectedCRC <= int_cmdInCRC;
            //
            //     end else if (!int_cmdInCounter) begin
            //         int_state <= StateRespIn+3;
            //     end
            // end
            //
            // StateRespIn+3: begin
            //     // Check for a bad CRC, or a bad stop bit
            //     $display("CRC: %b %b", int_respInExpectedCRC, int_cmdInReg);
            //     if ((int_respCheckCRC && int_respInExpectedCRC!==int_cmdInReg[7:1]) || !int_cmdInReg[0]) begin
            //         // TODO: handle bad response
            //         `ifdef SIM
            //             $display("Bad CRC or stop bit");
            //             $finish;
            //         `endif
            //
            //     end else begin
            //         `ifdef SIM
            //             $display("Response OK: %b %b", int_respInExpectedCRC, int_cmdInReg[7:1]);
            //         `endif
            //
            //         int_cmdInActive <= 0;
            //         int_cmdInCRCEn <= 0;
            //         int_state <= int_nextState;
            //     end
            // end
            
            
            
            
            // StateRespIn: begin
            //     int_cmdInCRCEn <= 1;
            //     int_state <= StateRespIn+1;
            // end
            //
            // // Wait for response to start
            // StateRespIn+1: begin
            //     if (!int_cmdIn) begin
            //         `ifdef SIM
            //             $display("StateRespIn: response started");
            //         `endif
            //         int_state <= StateRespIn+2;
            //
            //     end else begin
            //         int_cmdInCRCEn <= 0; // Reset the CRC since it should only begin when the message starts
            //         int_state <= StateRespIn;
            //     end
            // end
            //
            // // Clock in transmission bit (=0 when coming from SD card)
            // StateRespIn+2: begin
            //     int_state <= StateRespIn+3;
            // end
            //
            // StateRespIn+3: begin
            //     int_resp <= (int_resp<<1)|int_cmdIn;
            //
            //     // Valid transmission bit
            //     if (!int_cmdIn) begin
            //         `ifdef SIM
            //             $display("StateRespIn: transmission bit valid");
            //         `endif
            //         int_state <= StateRespIn+4;
            //
            //     // Invalid transmission bit
            //     end else begin
            //         `ifdef SIM
            //             $display("StateRespIn: transmission bit invalid");
            //         `endif
            //         // TODO: handle bad response
            //     end
            // end
            //
            // // Clock in response
            // StateRespIn+4: begin
            //     int_state <= StateRespIn+5;
            // end
            //
            // StateRespIn+5: begin
            //     int_resp <= (int_resp<<1)|int_cmdIn;
            //
            //     // Continue clocking in response
            //     if (int_counter != 1) begin
            //         int_counter <= int_counter-1;
            //         int_state <= StateRespIn+4;
            //
            //     // Clock-in CRC if requested
            //     end else if (int_respInCheckCRC) begin
            //         int_respInCheckCRC <= 0;
            //         int_respInExpectedCRC <= int_cmdInCRC;
            //         int_counter <= 7;
            //         int_state <= StateRespIn+6;
            //
            //     // Clock-in stop bit
            //     end else begin
            //         int_state <= StateRespIn+9;
            //     end
            // end
            //
            // // Clock-in and check CRC
            // StateRespIn+6: begin
            //     int_state <= StateRespIn+7;
            // end
            //
            // StateRespIn+7: begin
            //     int_resp <= (int_resp<<1)|int_cmdIn;
            //
            //     // Continue clocking-in CRC
            //     if (int_counter != 1) begin
            //         int_counter <= int_counter-1;
            //         int_state <= StateRespIn+6;
            //
            //     end else begin
            //         int_state <= StateRespIn+8;
            //     end
            // end
            //
            // StateRespIn+8: begin
            //     // CRC is valid: clock-in and check stop bit
            //     if (int_respInExpectedCRC == int_resp[6:0]) begin
            //         `ifdef SIM
            //             $display("StateRespIn: CRC valid");
            //         `endif
            //         int_state <= StateRespIn+9;
            //
            //     // CRC is invalid
            //     end else begin
            //         `ifdef SIM
            //             $display("StateRespIn: CRC invalid");
            //         `endif
            //         // TODO: handle bad response
            //     end
            // end
            //
            // // Clock-in and check stop bit
            // StateRespIn+9: begin
            //     int_state <= StateRespIn+10;
            // end
            //
            // StateRespIn+10: begin
            //     int_resp <= (int_resp<<1)|int_cmdIn;
            //
            //     // Correct stop bit: we're finished receiving the response
            //     if (int_cmdIn) begin
            //         `ifdef SIM
            //             $display("StateRespIn: stop bit valid");
            //         `endif
            //         int_state <= int_nextState;
            //
            //     // Incorrect stop bit:
            //     // TODO: handle bad response
            //     end else begin
            //         `ifdef SIM
            //             $display("StateRespIn: stop bit invalid");
            //         `endif
            //     end
            // end
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

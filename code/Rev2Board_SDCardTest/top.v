`include "../ClockGen.v"
`include "../AFIFO.v"
`include "../SDCardController.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps

module Debug #(
    // Max payload length (bytes)
    // *** Code needs to be updated below if this is changed!
    // *** See serialIn_payloadCounter case statement.
    parameter MsgMaxPayloadLen = 5
)(
    input wire                              clk,
    
    output wire[7:0]                        msgIn_type,
    output wire[7:0]                        msgIn_payloadLen,
    output wire[(MsgMaxPayloadLen*8)-1:0]   msgIn_payload,
    output wire                             msgIn_ready,
    input wire                              msgIn_trigger,
    
    input wire[7:0]                         msgOut_type,
    input wire[7:0]                         msgOut_payloadLen,
    input wire[7:0]                         msgOut_payload,
    output reg                              msgOut_payloadTrigger = 0,
    
    input wire                              debug_clk,
    input wire                              debug_di,
    output wire                             debug_do
);
    localparam MsgHeaderLen = 2; // Message header length (bytes)
    localparam MsgMaxLen = MsgHeaderLen+MsgMaxPayloadLen;
    
    assign msgIn_type = inq_readData[0*8+:8];
    assign msgIn_payloadLen = inq_readData[1*8+:8];
    assign msgIn_payload = inq_readData[2*8+:MsgMaxPayloadLen*8];
    assign msgIn_ready = inq_readOK;
    
    // ====================
    // In queue `inq`
    // ====================
    wire inq_rclk = clk;
    wire inq_readOK;
    wire inq_readTrigger = msgIn_trigger;
    wire[(MsgMaxLen*8)-1:0] inq_readData;
    wire inq_wclk = debug_clk;
    reg inq_writeTrigger = 0;
    wire[(MsgMaxLen*8)-1:0] inq_writeData = serialIn_msg;
    wire inq_writeOK;
    AFIFO #(.Width(MsgMaxLen*8), .Size(4)) inq(
        .rclk(inq_rclk),
        .rtrigger(inq_readTrigger),
        .rdata(inq_readData),
        .rok(inq_readOK),
        .wclk(inq_wclk),
        .wtrigger(inq_writeTrigger),
        .wdata(inq_writeData),
        .wok(inq_writeOK)
    );
    
    // ====================
    // Out queue `outq`
    // ====================
    wire outq_rclk = debug_clk;
    reg outq_readTrigger = 0;
    wire[7:0] outq_readData;
    wire outq_readOK;
    wire outq_wclk = clk;
    reg outq_writeTrigger = 0;
    reg[7:0] outq_writeData = 0;
    wire outq_writeOK;
    AFIFO #(.Width(8), .Size(8)) outq(
        .rclk(outq_rclk),
        .rtrigger(outq_readTrigger),
        .rdata(outq_readData),
        .rok(outq_readOK),
        .wclk(outq_wclk),
        .wtrigger(outq_writeTrigger),
        .wdata(outq_writeData),
        .wok(outq_writeOK)
    );
    
    // ====================
    // Message output / `clk` domain
    // ====================
    reg[2:0] msgOut_state = 0;
    always @(posedge clk) begin
        case (msgOut_state)
        // Send message type (byte 0)
        0: begin
            if (msgOut_type) begin
                outq_writeData <= msgOut_type;
                outq_writeTrigger <= 1;
                msgOut_state <= 1;
            end
        end
        
        // Send payload length (byte 1)
        1: begin
            if (outq_writeOK) begin
                outq_writeData <= msgOut_payloadLen;
                outq_writeTrigger <= 1;
                msgOut_state <= 2;
            end
        end
        
        // Delay while payload length is written
        2: begin
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
                
                // Trigger the initial payload byte, or provide the final payload trigger,
                // depending on whether there's payload data.
                msgOut_payloadTrigger <= 1;
                if (!msgOut_payloadLen) begin
                    msgOut_state <= 3;
                end else begin
                    msgOut_state <= 4;
                end
            end
        end
        
        // Delay before returning to first state
        3: begin
            msgOut_payloadTrigger <= 0;
            msgOut_state <= 0;
        end
        
        // Delay while first payload byte is loaded
        4: begin
            msgOut_payloadTrigger <= 0;
            msgOut_state <= 5;
        end
        
        5: begin
            outq_writeData <= msgOut_payload;
            outq_writeTrigger <= 1;
            msgOut_payloadTrigger <= 1;
            if (msgOut_payloadLen) begin
                msgOut_state <= 6;
            end else begin
                msgOut_state <= 7;
            end
        end
        
        // Delay while previous byte is written
        6: begin
            msgOut_payloadTrigger <= 0;
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
                msgOut_state <= 5;
            end
        end
        
        // Delay while final byte is written and client resets, before returning to first state
        7: begin
            msgOut_payloadTrigger <= 0;
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
                msgOut_state <= 0;
            end
        end
        endcase
    end
    
    
    
    
    
    
    
    
    
    // ====================
    // Serial IO / `debug_clk` domain
    // ====================
    reg[1:0] serialIn_state = 0;
    reg[8:0] serialIn_shiftReg = 0; // High bit is the end-of-data sentinel, and isn't transmitted
    wire[7:0] serialIn_byte = serialIn_shiftReg[7:0];
    wire serialIn_byteReady = serialIn_shiftReg[8];
    reg[(MsgMaxLen*8)-1:0] serialIn_msg;
    wire[7:0] serialIn_msgType = serialIn_msg[0*8+:8];
    wire[7:0] serialIn_payloadLen = serialIn_msg[1*8+:8];
    reg[7:0] serialIn_payloadCounter = 0;
    reg[1:0] serialOut_state = 0;
    reg[8:0] serialOut_shiftReg = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    assign debug_do = serialOut_shiftReg[8];
    always @(posedge debug_clk) begin
        if (serialIn_byteReady) begin
            serialIn_shiftReg <= {1'b1, debug_di};
        end else begin
            serialIn_shiftReg <= (serialIn_shiftReg<<1)|debug_di;
        end
        
        case (serialIn_state)
        0: begin
            // Initialize `serialIn_shiftReg` as if it was originally initialized to 1,
            // so that after the first clock it contains the sentinel and
            // the first bit of data.
            serialIn_shiftReg <= {1'b1, debug_di};
            serialIn_state <= 1;
        end
        
        // if (inq_writeTrigger && !inq_writeOK) begin
        //     // TODO: handle dropped bytes
        // end
        
        1: begin
            inq_writeTrigger <= 0; // Clear from state 3
            if (serialIn_byteReady) begin
                // Only transition states if we have a valid message type.
                // This way, new messages can occur at any byte boundary,
                // instead of every other byte if we required both
                // message type + payload length for every transmission.
                if (serialIn_byte) begin
                    serialIn_msg[0*8+:8] <= serialIn_byte;
                    serialIn_state <= 2;
                end
            end
        end
        
        2: begin
            if (serialIn_byteReady) begin
                serialIn_msg[1*8+:8] <= serialIn_byte;
                serialIn_payloadCounter <= 0;
                serialIn_state <= 3;
            end
        end
        
        3: begin
            if (serialIn_payloadCounter < serialIn_payloadLen) begin
                if (serialIn_byteReady) begin
                    // Only write while serialIn_payloadCounter < MsgMaxPayloadLen to prevent overflow.
                    if (serialIn_payloadCounter < MsgMaxPayloadLen) begin
                        case (serialIn_payloadCounter)
                        0: serialIn_msg[(0+2)*8+:8] <= serialIn_byte;
                        1: serialIn_msg[(1+2)*8+:8] <= serialIn_byte;
                        2: serialIn_msg[(2+2)*8+:8] <= serialIn_byte;
                        3: serialIn_msg[(3+2)*8+:8] <= serialIn_byte;
                        4: serialIn_msg[(4+2)*8+:8] <= serialIn_byte;
                        endcase
                    end
                    serialIn_payloadCounter <= serialIn_payloadCounter+1;
                end
            
            end else begin
                $display("Received message: msgType=%0d, payloadLen=%0d", serialIn_msgType, serialIn_payloadLen);
                // Only transmit non-nop messages
                if (serialIn_msgType) begin
                    inq_writeTrigger <= 1;
                end
                serialIn_state <= 1;
            end
        end
        endcase
        
        case (serialOut_state)
        0: begin
            // Initialize `serialOut_shiftReg` as if it was originally initialized to 1,
            // so that after the first clock cycle it contains the sentinel.
            serialOut_shiftReg <= 2'b10;
            serialOut_state <= 2;
        end
        
        1: begin
            serialOut_shiftReg <= serialOut_shiftReg<<1;
            outq_readTrigger <= 0;
            
            // If we successfully read a byte, shift it out
            if (outq_readOK) begin
                serialOut_shiftReg <= {outq_readData, 1'b1}; // Add sentinel to the end
            
            // Otherwise shift out a zero byte
            end else begin
                serialOut_shiftReg <= {8'b0, 1'b1}; // Add sentinel to the end
            end
            
            serialOut_state <= 2;
        end
        
        // Continue shifting out a byte
        2: begin
            serialOut_shiftReg <= serialOut_shiftReg<<1;
            if (serialOut_shiftReg[6:0] == 7'b1000000) begin
                outq_readTrigger <= 1;
                serialOut_state <= 1;
            end
        end
        endcase
    end
endmodule




module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0  /* synthesis syn_keep=1 */,
    
    output wire         sd_clk,
`ifdef SIM
    inout tri1          sd_cmd,
`else
    inout wire          sd_cmd  /* synthesis syn_keep=1 */,
`endif
    inout wire[3:0]     sd_dat,
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do
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
    
    // Not ideal to AND with a clock, since it can cause the resulting clock signal
    // to toggle anytime the other input changes.
    // We'll be safe though as long as we only toggle debug_cs while the clock is
    // low, which is our contract.
    wire debug_clkFiltered = debug_clk&debug_cs;
    
    
    
    
    // ====================
    // SD Card Controller
    // ====================
    reg         sd_cmd_trigger = 0;
    reg[37:0]   sd_cmd_cmd = 0;
    wire[135:0] sd_cmd_resp;
    wire        sd_cmd_done;
    SDCardController sdctrl(
        .clk12mhz(clk12mhz),
        
        .cmd_clk(clk),
        .cmd_trigger(sd_cmd_trigger),
        .cmd_cmd(sd_cmd_cmd),
        .cmd_resp(sd_cmd_resp),
        .cmd_done(sd_cmd_done),
        
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    
    
    
    
    
    
    
    // ====================
    // Debug I/O
    // ====================
    localparam MsgType_LEDSet           = 8'h01;
    
    localparam MsgType_MemRead          = 8'h02;
    localparam MsgType_MemData          = 8'h03;
    
    localparam MsgType_PixReg8          = 8'h04;
    localparam MsgType_PixReg16         = 8'h05;
    localparam MsgType_PixCapture       = 8'h06;
    localparam MsgType_PixSize          = 8'h07;
    localparam MsgType_PixData          = 8'h08;
    
    localparam MsgType_SDCmd            = 8'h09;
    localparam MsgType_SDResp           = 8'h0A;
    
    wire[7:0] debug_msgIn_type;
    wire[7:0] debug_msgIn_payloadLen;
    wire[5*8-1:0] debug_msgIn_payload;
    wire debug_msgIn_ready;
    reg debug_msgIn_trigger = 0;
    
    reg[7:0] debug_msgOut_type = 0;
    reg[7:0] debug_msgOut_payloadLen = 0;
    reg[7:0] debug_msgOut_payload = 0;
    wire debug_msgOut_payloadTrigger;
    Debug debug(
        .clk(clk),
        
        .msgIn_type(debug_msgIn_type),
        .msgIn_payloadLen(debug_msgIn_payloadLen),
        .msgIn_payload(debug_msgIn_payload),
        .msgIn_ready(debug_msgIn_ready),
        .msgIn_trigger(debug_msgIn_trigger),
        
        .msgOut_type(debug_msgOut_type),
        .msgOut_payloadLen(debug_msgOut_payloadLen),
        .msgOut_payload(debug_msgOut_payload),
        .msgOut_payloadTrigger(debug_msgOut_payloadTrigger),
        
        .debug_clk(debug_clkFiltered),
        .debug_di(debug_di),
        .debug_do(debug_do)
    );
    
    // ====================
    // Main
    // ====================
    function [15:0] DataFromAddr;
        input [24:0] addr;
        // DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
        DataFromAddr = addr[15:0];
        // DataFromAddr = 16'hFFFF;
        // DataFromAddr = 16'h0000;
        // DataFromAddr = 16'h7832;
        // DataFromAddr = 16'hCAFE;
    endfunction
    
    function [63:0] Min;
        input [63:0] a;
        input [63:0] b;
        Min = (a < b ? a : b);
    endfunction
    
    localparam StateInit        = 0;    // +0
    localparam StateHandleMsg   = 1;    // +2
    localparam StateSDCmd       = 4;    // +2
    reg[4:0] state = 0;
    reg[7:0] msgInType = 0;
    reg[5*8-1:0] msgInPayload = 0;
    
    always @(posedge clk) begin
        case (state)
        
        // Initialize the SDRAM
        StateInit+0: begin
            led <= 0;
            state <= StateHandleMsg;
        end
        
        
        
        
        
        
        
        // Accept new command
        StateHandleMsg+0: begin
            debug_msgIn_trigger <= 1;
            if (debug_msgIn_trigger && debug_msgIn_ready) begin
                debug_msgIn_trigger <= 0;
                
                msgInType <= debug_msgIn_type;
                msgInPayload <= debug_msgIn_payload;
                
                state <= StateHandleMsg+1;
            end
        end
        
        // Handle new command
        StateHandleMsg+1: begin
            // By default go to StateHandleMsg+2 next
            state <= StateHandleMsg+2;
            
            case (msgInType)
            default: begin
                debug_msgOut_type <= msgInType;
                debug_msgOut_payloadLen <= 0;
            end
            
            MsgType_LEDSet: begin
                `ifdef SIM
                    $display("MsgType_LEDSet: %0d", msgInPayload[0]);
                `endif
                led[0] <= msgInPayload[0];
                debug_msgOut_type <= MsgType_LEDSet;
                debug_msgOut_payloadLen <= 1;
            end
            
            MsgType_SDCmd: begin
                state <= StateSDCmd+0;
            end
            
            endcase
        end
        
        // Wait while the message is being sent
        StateHandleMsg+2: begin
            if (debug_msgOut_payloadTrigger) begin
                debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                debug_msgOut_payload <= 0;
                if (!debug_msgOut_payloadLen) begin
                    // Clear `debug_msgOut_type` to prevent another message from being sent.
                    debug_msgOut_type <= 0;
                    state <= StateHandleMsg;
                end
            end
        end
        
        StateSDCmd+0: begin
            sd_cmd_cmd <= {
                msgInPayload[5:0],      // command
                // msgInPayload[8:39],   // arg0
                msgInPayload[1*8+:8],   // arg0
                msgInPayload[2*8+:8],   // arg1
                msgInPayload[3*8+:8],   // arg2
                msgInPayload[4*8+:8]    // arg3
            };
            sd_cmd_trigger <= 1;
            state <= StateSDCmd+1;
        end
        
        StateSDCmd+1: begin
            sd_cmd_trigger <= 0;
            // Wait until the SD command is complete
            if (sd_cmd_done) begin
                `ifdef SIM
                    $display("SD command completed, sending response back to host: %b", sd_cmd_resp);
                `endif
                debug_msgOut_type <= MsgType_SDResp;
                debug_msgOut_payloadLen <= 18;
                state <= StateSDCmd+2;
            end
        end
        
        StateSDCmd+2: begin
            // Send the SD command response back to the host
            if (debug_msgOut_payloadTrigger) begin
                debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                case (debug_msgOut_payloadLen)
                18: debug_msgOut_payload <= 1; // status
                17: debug_msgOut_payload <= sd_cmd_resp[(17*8)-1-:8];
                16: debug_msgOut_payload <= sd_cmd_resp[(16*8)-1-:8];
                15: debug_msgOut_payload <= sd_cmd_resp[(15*8)-1-:8];
                14: debug_msgOut_payload <= sd_cmd_resp[(14*8)-1-:8];
                13: debug_msgOut_payload <= sd_cmd_resp[(13*8)-1-:8];
                12: debug_msgOut_payload <= sd_cmd_resp[(12*8)-1-:8];
                11: debug_msgOut_payload <= sd_cmd_resp[(11*8)-1-:8];
                10: debug_msgOut_payload <= sd_cmd_resp[(10*8)-1-:8];
                 9:  debug_msgOut_payload <= sd_cmd_resp[(9*8)-1-:8];
                 8:  debug_msgOut_payload <= sd_cmd_resp[(8*8)-1-:8];
                 7:  debug_msgOut_payload <= sd_cmd_resp[(7*8)-1-:8];
                 6:  debug_msgOut_payload <= sd_cmd_resp[(6*8)-1-:8];
                 5:  debug_msgOut_payload <= sd_cmd_resp[(5*8)-1-:8];
                 4:  debug_msgOut_payload <= sd_cmd_resp[(4*8)-1-:8];
                 3:  debug_msgOut_payload <= sd_cmd_resp[(3*8)-1-:8];
                 2:  debug_msgOut_payload <= sd_cmd_resp[(2*8)-1-:8];
                 1:  debug_msgOut_payload <= sd_cmd_resp[(1*8)-1-:8];
                 0: begin
                    // Clear `debug_msgOut_type` to prevent another message from being sent.
                    debug_msgOut_type <= 0;
                    state <= StateHandleMsg;
                end
                endcase
            end
        end
        
        endcase
    end
    
    
// `ifdef SIM
//     initial begin
//         $dumpfile("top.vcd");
//         $dumpvars(0, Top);
//     end
//
//     initial begin
//         #1000000;
//         $finish;
//     end
// `endif
    
    
    
    
    
    
`ifdef SIM
    reg sim_debug_clk = 0;
    reg sim_debug_cs = 0;
    reg[7:0] sim_debug_di_shiftReg = 0;
    
    assign debug_clk = sim_debug_clk;
    assign debug_cs = sim_debug_cs;
    assign debug_di = sim_debug_di_shiftReg[7];
    
    reg sim_pix_dclk = 0;
    reg[11:0] sim_pix_d = 0;
    reg sim_pix_fv = 0;
    reg sim_pix_lv = 0;
    
    assign pix_dclk = sim_pix_dclk;
    assign pix_d = sim_pix_d;
    assign pix_fv = sim_pix_fv;
    assign pix_lv = sim_pix_lv;
    
    task WriteByte(input[7:0] b);
        sim_debug_di_shiftReg = b;
        repeat (8) begin
            wait (sim_debug_clk);
            wait (!sim_debug_clk);
            sim_debug_di_shiftReg = sim_debug_di_shiftReg<<1;
        end
    endtask
    
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        // Wait for ClockGen to start its clock
        wait(clk);
        #100;
        
        wait (!sim_debug_clk);
        sim_debug_cs = 1;
        
        WriteByte(MsgType_SDCmd);   // Message type
        WriteByte(8'h5);            // Payload length
        WriteByte(8'h01);           // Payload0: command
        WriteByte(8'h42);           // Payload1: arg0
        WriteByte(8'h43);           // Payload2: arg1
        WriteByte(8'h44);           // Payload3: arg2
        WriteByte(8'h45);           // Payload4: arg3
        
        // WriteByte(MsgType_LEDSet);  // Message type
        // WriteByte(8'h1);            // Payload length
        // WriteByte(8'h1);            // Payload
        
        // WriteByte(MsgType_PixReg8);     // Message type
        // WriteByte(8'h4);                // Payload length
        // WriteByte(8'h1);                // Payload0: write
        // WriteByte(8'h34);               // Payload1: addr0
        // WriteByte(8'h12);               // Payload2: addr1
        // WriteByte(8'h42);               // Payload3: value
        //
        // WriteByte(MsgType_PixReg8);     // Message type
        // WriteByte(8'h4);                // Payload length
        // WriteByte(8'h0);                // Payload0: write
        // WriteByte(8'h34);               // Payload1: addr0
        // WriteByte(8'h12);               // Payload2: addr1
        // WriteByte(8'h42);               // Payload3: value
        //
        // WriteByte(MsgType_PixReg16);    // Message type
        // WriteByte(8'h5);                // Payload length
        // WriteByte(8'h0);                // Payload0: write
        // WriteByte(8'h34);               // Payload1: addr0
        // WriteByte(8'h12);               // Payload2: addr1
        // WriteByte(8'hFE);               // Payload3: value0
        // WriteByte(8'hCA);               // Payload4: value1
        
        #1000000;
        $finish;
    end
    
    // ====================
    // sim_debug_clk driver
    // ====================
    initial begin
        // Wait for ClockGen to start its clock
        wait(clk);
        #100;
        
        forever begin
            sim_debug_clk = 0;
            #10;
            sim_debug_clk = 1;
            #10;
        end
    end
    
    
    
    
    
    
    
    // ====================
    // SD card emulator
    //   Receive commands, issue responses
    // ====================
    reg[47:0] sim_cmdIn = 0;
    reg[47:0] sim_respOut = 0;
    reg sim_cmdOut = 1'bz;
    assign sd_cmd = sim_cmdOut;
    
    initial begin
        forever begin
            wait(sd_clk);
            
            if (!sd_cmd) begin
                // Receive command
                reg[7:0] i;
                for (i=0; i<48; i++) begin
                    sim_cmdIn = (sim_cmdIn<<1)|sd_cmd;
                    wait(!sd_clk);
                    wait(sd_clk);
                end
                
                $display("Received command: %b [ preamble: %b, index: %0d, arg: 0x%x, crc: %b, stop: %b ]",
                    sim_cmdIn,
                    sim_cmdIn[47:46],   // preamble
                    sim_cmdIn[45:40],   // index
                    sim_cmdIn[39:8],    // arg
                    sim_cmdIn[7:1],     // crc
                    sim_cmdIn[0],       // stop bit
                );
                
                // Issue response
                sim_respOut = {47'b0, 1'b1};
                $display("Sending response: %b", sim_respOut);
                for (i=0; i<48; i++) begin
                    wait(!sd_clk);
                    sim_cmdOut = sim_respOut[47];
                    sim_respOut = sim_respOut<<1;
                    wait(sd_clk);
                end
                wait(!sd_clk);
                sim_cmdOut = 1'bz;
            end
            
            wait(!sd_clk);
        end
    end
    
    
    
`endif
    
    
    
    
    
endmodule

`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../AFIFO.v"
`include "../SDRAMController.v"
`include "../PixI2CMaster.v"

module Delay #(
    parameter Count = 1
)(
    input wire in,
    output wire out
);
    wire[(Count*2)-1:0] bits /* synthesis syn_keep=1 */;
    
    assign bits[0] = !in;
    assign out = bits[(Count*2)-1];
    
    genvar i;
    for (i=1; i<Count*2; i=i+1) begin
        assign bits[i] = !bits[i-1];
    end
endmodule


// Sync:
// Synchronizes an asynchronous signal into a clock domain
module Sync(
    input wire in,
    
    input wire out_clk,
    output reg out = 0
);
    reg pipe = 0;
    always @(posedge out_clk)
        { out, pipe } <= { pipe, in };
endmodule







// SyncPulse:
// Transmits a single-clock pulse across clock domains
// Pulses can be dropped if they occur more rapidly than they can be acknowledged.
module SyncPulse(
    input wire in_clk,
    input wire in,
    
    input wire out_clk,
    output wire out
);
    reg in_req = 0;
    wire in_ack;
    wire idle = !in_req && !in_ack;
    always @(posedge in_clk) begin
    	if (idle && in)     in_req <= 1;
    	else if (in_ack)    in_req <= 0;
    end
    
    wire out_req;
    Sync syncReq(.in(in_req), .out_clk(out_clk), .out(out_req));
    Sync syncAck(.in(out_req), .out_clk(in_clk), .out(in_ack));
    
    reg out_lastReq = 0;
    assign out = out_lastReq && !out_req; // Out pulse occurs upon negative edge of out_req.
    always @(posedge out_clk) out_lastReq <= out_req;
endmodule









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
        .r(inq_readTrigger),
        .rd(inq_readData),
        .rok(inq_readOK),
        .wclk(inq_wclk),
        .w(inq_writeTrigger),
        .wd(inq_writeData),
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
        .r(outq_readTrigger),
        .rd(outq_readData),
        .rok(outq_readOK),
        .wclk(outq_wclk),
        .w(outq_writeTrigger),
        .wd(outq_writeData),
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
                // $display("Received message: msgType=%0d, payloadLen=%0d", serialIn_msgType, serialIn_payloadLen);
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





module PixController #(
    parameter ClkFreq = 12000000,       // `clk` frequency
    parameter ExtClkFreq = 12000000     // Image sensor's external clock frequency
)(
    input wire          clk,
    
    input wire          capture_trigger,    // Pulse for a single clock to trigger a new capture
    output wire         capture_done,       // Pulsed for a single clock to indicate that there
                                            // are no more pixels in the requested frame
    output wire[11:0]   pixel,
    output wire         pixel_ready,
    input wire          pixel_trigger,
    
    output reg          pix_rst_,
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv
    
    // output wire         pix_sclk,
    // inout wire          pix_sdata
);
    function [63:0] DivCeil;
        input [63:0] n;
        input [63:0] d;
        begin
            DivCeil = (n+d-1)/d;
        end
    endfunction
    
    // Clocks() returns the minimum number of `ClkFreq` clock cycles
    // for >= `t` nanoseconds to elapse. For example, if t=5ns, and
    // the clock period is 3ns, Clocks(t=5,sub=0) will return 2.
    // `sub` is subtracted from that value, with the result clipped to zero.
    function [63:0] Clocks;
        input [63:0] t;
        input [63:0] sub;
        begin
            Clocks = DivCeil(t*ClkFreq, 1000000000);
            if (Clocks >= sub) Clocks = Clocks-sub;
            else Clocks = 0;
        end
    endfunction
    
    function [63:0] Max;
        input [63:0] a;
        input [63:0] b;
        Max = (a > b ? a : b);
    endfunction
    
    // Clocks for EXTCLK to settle
    // EXTCLK (the SiTime 12MHz clock) takes up to 150ms to settle,
    // but ice40 configuration takes 70 ms, so we only need to wait 80 ms.
    localparam SettleDelay = Clocks(80000000, 0);
    // Clocks to assert pix_rst_ (1ms)
    localparam ResetDelay = Clocks(1000000, 0);
    // Clocks to wait for sensor to initialize (150k EXTCLKs)
    localparam InitDelay = Clocks(((150000*1000000000)/ExtClkFreq), 0);
    // Width of `delay`
    localparam DelayWidth = Max(Max($clog2(SettleDelay+1), $clog2(ResetDelay+1)), $clog2(InitDelay+1));
    
    reg[1:0] state = 0;
    reg[DelayWidth-1:0] delay = 0;
    always @(posedge clk) begin
        case (state)
        
        // Wait for EXTCLK to settle
        0: begin
            pix_rst_ <= 1;
            delay <= SettleDelay;
            state <= 1;
        end
        
        // Assert pix_rst_ for ResetDelay (1ms)
        1: begin
            if (delay) begin
                delay <= delay-1;
            end else begin
                pix_rst_ <= 0;
                delay <= ResetDelay;
                state <= 2;
            end
        end
        
        // Deassert pix_rst_ and wait InitDelay
        2: begin
            if (delay) begin
                delay <= delay-1;
            end else begin
                pix_rst_ <= 1;
                delay <= InitDelay;
                state <= 3;
            end
        end
        
        3: begin
            // - Write R0x3052 = 0xA114 to configure the internal register initialization process.
            // - Write R0x304A = 0x0070 to start the internal register initialization process.
            // - Wait 150,000 EXTCLK periods
            // - Configure PLL, output, and image settings to desired values.
            // - Wait 1ms for the PLL to lock.
            // - Set streaming mode (R0x301A[2] = 1).
        end
        endcase
    end
    
    
    
    
    reg pixq_capture = 0;
    wire pixq_rclk = clk;
    wire pixq_readOK;
    wire pixq_readTrigger = pixel_trigger;
    wire[15:0] pixq_readData;
    wire pixq_wclk = pix_dclk;
    wire pixq_writeTrigger = pix_lv && pixq_capture;
    wire[15:0] pixq_writeData = pix_d;
    wire pixq_writeOK;
    AFIFO #(.Width(16), .Size(256)) pixq(
        .rclk(pixq_rclk),
        .r(pixq_readTrigger),
        .rd(pixq_readData),
        .rok(pixq_readOK),
        .wclk(pixq_wclk),
        .w(pixq_writeTrigger),
        .wd(pixq_writeData),
        .wok(pixq_writeOK)
    );
    
    assign pixel[11:0] = pixq_readData[11:0];
    assign pixel_ready = pixq_readOK;
    
    // Synchronize `capture_trigger` pulse into `pix_dclk` domain
    wire captureReqPulse;
    SyncPulse sync1(.in_clk(clk), .in(capture_trigger), .out_clk(pix_dclk), .out(captureReqPulse));
    
    // TODO: there's probably a race between draining the AFIFO pixels and the `capture_done`
    // signal -- the `capture_done` can probably arrive before we're done draining the pixels...
    
    // Synchronize `frameEndPulse` pulse into `clk` domain
    SyncPulse sync2(.in_clk(pix_dclk), .in(frameEndPulse), .out_clk(clk), .out(capture_done));
    
    reg captureReq = 0;
    reg lastFrameValid = 0;
    reg frameEndPulse = 0;
    always @(posedge pix_dclk) begin
        // Frame start
        if (!lastFrameValid && pix_fv) begin
            pixq_capture <= captureReq;
        
        // Frame end
        end else if (lastFrameValid && !pix_fv) begin
            captureReq <= 0;
            pixq_capture <= 0;
            frameEndPulse <= 1;
        end
        
        // Latch `captureReq` until we're ready to service it (at the start of a new frame)
        if (captureReqPulse) captureReq <= 1;
        // Reset frameEndPulse to ensure it's a single pulse
        if (frameEndPulse) frameEndPulse <= 0;
        // Remember `pix_fv`
        lastFrameValid <= pix_fv;
    end
    
    
    
    
endmodule



module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0,
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq,
    
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    input wire          pix_rst_,
    output wire         pix_i2c_clk,
`ifdef SIM
    inout tri1          pix_i2c_data,
`else
    inout wire          pix_i2c_data,
`endif
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do
);
    // ====================
    // Clock PLL (81 MHz)
    // ====================
    localparam ClkFreq = 81000000;
    wire pllClk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(pllClk));
    
    assign ram_clk = pllClk;
    
    wire clk;
    Delay #(.Count(1)) clkDelay(.in(pllClk), .out(clk));
    
    // Not ideal to AND with a clock, since it can cause the resulting clock signal
    // to toggle anytime the other input changes.
    // We'll be safe though as long as we only toggle debug_cs while the clock is
    // low, which is our contract.
    wire debug_clkFiltered = debug_clk&debug_cs;
    
    
    
    
    
    
    // ====================
    // SDRAM Controller
    // ====================
    localparam RAM_Size = 'h2000000;
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;
    
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  ram_cmdWriteData = 0;
    wire[RAM_DataWidth-1:0] ram_cmdReadData;
    wire                    ram_cmdReadDataValid;

    SDRAMController #(
        .ClkFreq(ClkFreq)
    ) sdramController(
        .clk(clk),

        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(ram_cmdReadData),
        .cmdReadDataValid(ram_cmdReadDataValid),

        // .ram_clk(ram_clk),
        .ram_cke(ram_cke),
        .ram_ba(ram_ba),
        .ram_a(ram_a),
        .ram_cs_(ram_cs_),
        .ram_ras_(ram_ras_),
        .ram_cas_(ram_cas_),
        .ram_we_(ram_we_),
        .ram_dqm(ram_dqm),
        .ram_dq(ram_dq)
    );
    
    
    
    // ====================
    // Pix Controller
    // ====================
    reg pix_captureTrigger = 0;
    wire pix_captureDone;
    wire[11:0] pix_pixel;
    wire pix_pixelReady;
    reg pix_pixelTrigger = 0;
    PixController #(
        .ExtClkFreq(12000000),
        .ClkFreq(ClkFreq)
    ) pixController(
        .clk(clk),
        
        .capture_trigger(pix_captureTrigger),
        .capture_done(pix_captureDone),
        
        .pixel(pix_pixel),
        .pixel_ready(pix_pixelReady),
        .pixel_trigger(pix_pixelTrigger),
        
        .pix_rst_(pix_rst_),
        .pix_dclk(pix_dclk),
        .pix_d(pix_d),
        .pix_fv(pix_fv),
        .pix_lv(pix_lv)
    );
    
    
    // ====================
    // Pix I2C Master
    // ====================
    
    wire[6:0] pix_i2c_cmd_slaveAddr = 7'h10;    // 7-bit address
                                                // 8-bit address is 0x20 (write) / 0x21 (read), per the datasheet,
                                                // where the low bit is the transaction direction (write=0 / read=1)
    reg pix_i2c_cmd_write = 0;
    reg[15:0] pix_i2c_cmd_regAddr = 0;
    reg[15:0] pix_i2c_cmd_writeData = 0;
    wire[15:0] pix_i2c_cmd_readData;
    reg[1:0] pix_i2c_cmd_dataLen;
    wire pix_i2c_cmd_done;
    wire pix_i2c_cmd_ok;
    PixI2CMaster #(
        .ClkFreq(ClkFreq),
        .I2CClkFreq(100000)
    ) pixI2CMaster(
        .clk(clk),
        
        .cmd_slaveAddr(pix_i2c_cmd_slaveAddr),
        .cmd_write(pix_i2c_cmd_write),
        .cmd_regAddr(pix_i2c_cmd_regAddr),
        .cmd_writeData(pix_i2c_cmd_writeData),
        .cmd_readData(pix_i2c_cmd_readData),
        .cmd_dataLen(pix_i2c_cmd_dataLen),
        .cmd_done(pix_i2c_cmd_done),
        .cmd_ok(pix_i2c_cmd_ok),
        
        .i2c_clk(pix_i2c_clk),
        .i2c_data(pix_i2c_data)
    );
    
    
    
    
    
    
    // ====================
    // Debug I/O
    // ====================
    localparam MsgType_SetLED           = 8'h01;
    localparam MsgType_ReadMem          = 8'h02;
    localparam MsgType_PixReg8          = 8'h03;
    localparam MsgType_PixReg16         = 8'h04;
    localparam MsgType_PixCapture       = 8'h05;
    
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
        // DataFromAddr = addr[15:0];
        // DataFromAddr = 16'hFFFF;
        // DataFromAddr = 16'h0000;
        // DataFromAddr = 16'h7832;
        DataFromAddr = 16'hCAFE;
    endfunction
    
    function [63:0] Min;
        input [63:0] a;
        input [63:0] b;
        Min = (a < b ? a : b);
    endfunction
    
    localparam StateInit        = 0;    // +0
    localparam StateHandleMsg   = 1;    // +2
    localparam StateReadMem     = 4;    // +4
    localparam StatePixReg8     = 9;    // +2
    localparam StatePixReg16    = 12;   // +2
    localparam StatePixCapture  = 15;   // +3
    
    reg[4:0] state = 0;
    reg[7:0] msgInType = 0;
    reg[5*8-1:0] msgInPayload = 0;
    reg[15:0] ramWord = 0;
    reg ramWordTrigger = 0;
    reg[7:0] ramReadTakeoffCounter = 0;
    reg[7:0] ramReadLandCounter = 0;
    reg[15:0] mem[127:0];
    reg[7:0] memReadCounter = 0;
    reg[6:0] memAddr; // Don't init with memAddr=0, otherwise Icestorm won't infer a RAM for `mem`
    
`ifdef SIM
    initial memAddr = 0; // For simulation (see memAddr comment above)
`endif
    
    always @(posedge clk) begin
        case (state)
        
        // Initialize the SDRAM
        StateInit: begin
`ifdef SIM
            state <= StateHandleMsg;
`else
            if (!ram_cmdTrigger) begin
                ram_cmdTrigger <= 1;
                ram_cmdAddr <= 0;
                ram_cmdWrite <= 1;
                ram_cmdWriteData <= DataFromAddr(0);

            end else if (ram_cmdReady) begin
                ram_cmdAddr <= ram_cmdAddr+1;
                ram_cmdWriteData <= DataFromAddr(ram_cmdAddr+1);

                if (ram_cmdAddr == RAM_Size-1) begin
                    ram_cmdTrigger <= 0;
                    state <= StateHandleMsg;
                end
            end
`endif
        end
        
        
        
        
        
        
        
        // Accept new command
        StateHandleMsg: begin
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
            
            MsgType_ReadMem: begin
                ram_cmdAddr <= 0;
                ram_cmdWrite <= 0;
                state <= StateReadMem;
            end
            
            MsgType_SetLED: begin
                $display("MsgType_SetLED: %0d", msgInPayload[0]);
                led[0] <= msgInPayload[0];
                debug_msgOut_type <= MsgType_SetLED;
                debug_msgOut_payloadLen <= 1;
            end
            
            MsgType_PixReg8: begin
                state <= StatePixReg8;
            end
            
            MsgType_PixReg16: begin
                state <= StatePixReg16;
            end
            
            MsgType_PixCapture: begin
                state <= StatePixCapture;
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
        
        
        
        
        
        // Start reading memory
        StateReadMem: begin
            ram_cmdAddr <= 0;
            ram_cmdWrite <= 0;
            state <= StateReadMem+1;
        end
        
        StateReadMem+1: begin
            ram_cmdTrigger <= 1;
            ramReadTakeoffCounter <= Min(8'h7F, RAM_Size-ram_cmdAddr);
            ramReadLandCounter <= Min(8'h7F, RAM_Size-ram_cmdAddr);
            memAddr <= 0;
            state <= StateReadMem+2;
        end
        
        // Continue reading memory
        StateReadMem+2: begin
            // Handle the read being accepted
            if (ram_cmdReady && ram_cmdTrigger) begin
                ram_cmdAddr <= ram_cmdAddr+1;
                
                // Stop triggering when we've issued all the read commands
                ramReadTakeoffCounter <= ramReadTakeoffCounter-1;
                if (ramReadTakeoffCounter == 1) begin
                    ram_cmdTrigger <= 0;
                end
            end
            
            if (ramWordTrigger) begin
                ramWordTrigger <= 0;
                
                mem[memAddr] <= ramWord;
                memAddr <= memAddr+1;
                
                // Next state after we've received all the bytes
                ramReadLandCounter <= ramReadLandCounter-1;
                if (ramReadLandCounter == 1) begin
                    state <= StateReadMem+3;
                end
            end
            
            // Write incoming data into `ramWord`
            if (ram_cmdReadDataValid) begin
                ramWord <= ram_cmdReadData;
                ramWordTrigger <= 1;
            end
        end
        
        // Start sending the data
        StateReadMem+3: begin
            debug_msgOut_type <= MsgType_ReadMem;
            debug_msgOut_payloadLen <= memAddr<<1; // memAddr*2 for the number of bytes
            memReadCounter <= 0;
            memAddr <= 0;
            state <= StateReadMem+4;
        end
        
        // Send the data
        StateReadMem+4: begin
            // Continue sending data
            if (debug_msgOut_payloadTrigger) begin
                debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                
                if (debug_msgOut_payloadLen) begin
                    if (!memReadCounter[0])
                        debug_msgOut_payload <= mem[memAddr][7:0]; // Low byte
                    else
                        debug_msgOut_payload <= mem[memAddr][15:8]; // High byte
                    memReadCounter <= memReadCounter+1;
                    memAddr <= (memReadCounter+1)>>1;
                
                end else begin
                    // We're finished with this chunk.
                    // Clear `debug_msgOut_type` to prevent another message from being sent.
                    debug_msgOut_type <= 0;
                    
                    // Start on the next chunk, or stop if we've read everything.
                    if (ram_cmdAddr == 0) begin
                        state <= StateHandleMsg;
                    end else begin
                        state <= StateReadMem+1;
                    end
                end
            end
        end
        
        
        
        
        
        
        StatePixReg8: begin
            $display("MsgType_PixReg8{write=%0d, addr=%04x, data=%02x}", msgInPayload[0], msgInPayload[1*8+:16], msgInPayload[3*8+:8]);
            pix_i2c_cmd_write <= msgInPayload[0];
            pix_i2c_cmd_regAddr <= msgInPayload[1*8+:16]; // Little endian address
            pix_i2c_cmd_writeData <= msgInPayload[3*8+:8];
            pix_i2c_cmd_dataLen <= 1;
            state <= StatePixReg8+1;
        end
        
        StatePixReg8+1: begin
            if (pix_i2c_cmd_done) begin
                pix_i2c_cmd_dataLen <= 0; // Clear i2c command to prevent it from executing
                
                debug_msgOut_type <= MsgType_PixReg8;
                debug_msgOut_payloadLen <= 5;
                state <= StatePixReg8+2;
            end
        end
        
        StatePixReg8+2: begin
            if (debug_msgOut_payloadTrigger) begin
                debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                case (debug_msgOut_payloadLen)
                5: debug_msgOut_payload <= pix_i2c_cmd_write;
                4: debug_msgOut_payload <= pix_i2c_cmd_regAddr[0*8+:8];
                3: debug_msgOut_payload <= pix_i2c_cmd_regAddr[1*8+:8];
                2: debug_msgOut_payload <= pix_i2c_cmd_readData[0*8+:8];
                1: debug_msgOut_payload <= pix_i2c_cmd_ok;
                0: begin
                    // Clear `debug_msgOut_type` to prevent another message from being sent.
                    debug_msgOut_type <= 0;
                    state <= StateHandleMsg;
                end
                endcase
            end
        end
        
        
        
        
        
        
        
        StatePixReg16: begin
            $display("MsgType_PixReg16{write=%0d, addr=%04x, data=%04x}", msgInPayload[0], msgInPayload[1*8+:16], msgInPayload[3*8+:16]);
            pix_i2c_cmd_write <= msgInPayload[0];
            pix_i2c_cmd_regAddr <= msgInPayload[1*8+:16]; // Little endian address
            pix_i2c_cmd_writeData <= msgInPayload[3*8+:16];
            pix_i2c_cmd_dataLen <= 2;
            state <= StatePixReg16+1;
        end
        
        StatePixReg16+1: begin
            if (pix_i2c_cmd_done) begin
                pix_i2c_cmd_dataLen <= 0; // Clear i2c command to prevent it from executing
                
                debug_msgOut_type <= MsgType_PixReg16;
                debug_msgOut_payloadLen <= 6;
                state <= StatePixReg16+2;
            end
        end
        
        StatePixReg16+2: begin
            if (debug_msgOut_payloadTrigger) begin
                debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                case (debug_msgOut_payloadLen)
                6: debug_msgOut_payload <= pix_i2c_cmd_write;
                5: debug_msgOut_payload <= pix_i2c_cmd_regAddr[0*8+:8];
                4: debug_msgOut_payload <= pix_i2c_cmd_regAddr[1*8+:8];
                3: debug_msgOut_payload <= pix_i2c_cmd_readData[0*8+:8];
                2: debug_msgOut_payload <= pix_i2c_cmd_readData[1*8+:8];
                1: debug_msgOut_payload <= pix_i2c_cmd_ok;
                0: begin
                    // Clear `debug_msgOut_type` to prevent another message from being sent.
                    debug_msgOut_type <= 0;
                    state <= StateHandleMsg;
                end
                endcase
            end
        end
        
        
        
        
        StatePixCapture: begin
            pix_captureTrigger <= 1;
            state <= StatePixCapture+1;
        end
        
        StatePixCapture+1: begin
            pix_captureTrigger <= 0;
            pix_pixelTrigger <= 1;
            
            ram_cmdAddr <= 0;
            ram_cmdWrite <= 1;
            ram_cmdTrigger <= 0;
            
            state <= StatePixCapture+2;
        end
        
        StatePixCapture+2: begin
            led[3] <= 1;
            
            // Handle writing a pixel to RAM
            if (ram_cmdTrigger && ram_cmdReady) begin
                ram_cmdAddr <= ram_cmdAddr+1;
                ram_cmdTrigger <= 0;
                
                // If a pixel is in our overflow register, move it to `ram_cmdWriteData`
                if (ramWordTrigger) begin
                    ram_cmdWriteData <= ramWord;
                    ram_cmdTrigger <= 1;
                    ramWordTrigger <= 0;
                    pix_pixelTrigger <= 1;
                end
            end
            
            // Handle reading a new pixel into `ram_cmdWriteData`, or an overflow register
            if (pix_pixelReady && pix_pixelTrigger) begin
                // Store pixel in `ram_cmdWriteData` if it's available
                if (!ram_cmdTrigger || ram_cmdReady) begin
                    ram_cmdWriteData <= pix_pixel;
                    ram_cmdTrigger <= 1;
                
                // Otherwise store the pixel in our overflow register and stall
                // reading more pixels until the RAM catches up
                end else begin
                    ramWord <= pix_pixel;
                    ramWordTrigger <= 1;
                    pix_pixelTrigger <= 0;
                end
            end
            
            // if (pix_captureDone) begin
            //     led[3] <= !led[3];
            //
            //     debug_msgOut_type <= MsgType_PixCapture;
            //     debug_msgOut_payloadLen <= 4;
            //     state <= StatePixCapture+3;
            // end
        end
        
        StatePixCapture+3: begin
            if (debug_msgOut_payloadTrigger) begin
                debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                case (debug_msgOut_payloadLen)
                4: debug_msgOut_payload <= ram_cmdAddr[0*8+:8];
                3: debug_msgOut_payload <= ram_cmdAddr[1*8+:8];
                2: debug_msgOut_payload <= ram_cmdAddr[2*8+:8];
                1: debug_msgOut_payload <= {7'b0, ram_cmdAddr[24]};
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
    
    
`ifdef SIM
    reg sim_debug_clk = 0;
    reg sim_debug_cs = 0;
    reg[7:0] sim_debug_di_shiftReg = 0;
    
    assign debug_clk = sim_debug_clk;
    assign debug_cs = sim_debug_cs;
    assign debug_di = sim_debug_di_shiftReg[7];
    
    task WriteByte(input[7:0] b);
        sim_debug_di_shiftReg = b;
        repeat (8) begin
            wait (sim_debug_clk);
            wait (!sim_debug_clk);
            sim_debug_di_shiftReg = sim_debug_di_shiftReg<<1;
        end
    endtask
    
    
    // assign debug_di = 1;
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
        
        // Wait for ClockGen to start its clock
        wait(clk);
        #100;
        
        wait (!sim_debug_clk);
        sim_debug_cs = 1;
        
        // WriteByte(MsgType_SetLED);  // Message type
        // WriteByte(8'h1);            // Payload length
        // WriteByte(8'h1);            // Payload
        
        WriteByte(MsgType_PixReg8);     // Message type
        WriteByte(8'h4);                // Payload length
        WriteByte(8'h1);                // Payload0: write
        WriteByte(8'h34);               // Payload1: addr0
        WriteByte(8'h12);               // Payload2: addr1
        WriteByte(8'h42);               // Payload3: value

        WriteByte(MsgType_PixReg8);     // Message type
        WriteByte(8'h4);                // Payload length
        WriteByte(8'h0);                // Payload0: write
        WriteByte(8'h34);               // Payload1: addr0
        WriteByte(8'h12);               // Payload2: addr1
        WriteByte(8'h42);               // Payload3: value
        
        WriteByte(MsgType_PixReg16);    // Message type
        WriteByte(8'h5);                // Payload length
        WriteByte(8'h0);                // Payload0: write
        WriteByte(8'h34);               // Payload1: addr0
        WriteByte(8'h12);               // Payload2: addr1
        WriteByte(8'hFE);               // Payload3: value0
        WriteByte(8'hCA);               // Payload4: value1
        
        #1000000;
        $finish;
    end
    
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
`endif
    
endmodule

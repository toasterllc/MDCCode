`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../AFIFO.v"
// `include "../SDRAMController.v"

module Debug(
    input wire                      clk,
    
    output wire[(MsgMaxLen*8)-1:0]  msgIn_data,
    output wire                     msgIn_ready,
    input wire                      msgIn_trigger,
    
    input wire[7:0]                 msgOut_type,
    input wire[7:0]                 msgOut_payloadLen,
    input wire[7:0]                 msgOut_payload,
    output reg                      msgOut_payloadTrigger = 0,
    
    input wire                      debug_clk,
    input wire                      debug_di,
    output wire                     debug_do
);
    localparam MsgHeaderLen = 2; // Message header length (bytes)
    localparam MsgMaxPayloadLen = 4; // Max payload length (bytes)
    localparam MsgMaxLen = MsgHeaderLen+MsgMaxPayloadLen;
    
    assign msgIn_data = inq_readData;
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
    reg[1:0] msgOut_state = 0;
    always @(posedge clk) begin
        case (msgOut_state)
        // Send message type (byte 0)
        0: begin
            msgOut_payloadTrigger <= 0; // Necessary to clear the final msgOut_payloadTrigger=1 from state 2
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
        
        // Send the message payload
        2: begin
            if (msgOut_payloadLen) begin
                outq_writeData <= msgOut_payload;
                outq_writeTrigger <= 1;
                msgOut_payloadTrigger <= 1;
                msgOut_state <= 3;
            end else begin
                msgOut_payloadTrigger <= 1;
                msgOut_state <= 0;
            end
        end
        
        // Delay state while the next message byte is triggered
        3: begin
            msgOut_payloadTrigger <= 0;
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
                msgOut_state <= 3;
            end
        end
        endcase
    end
    
    
    
    
    
    
    
    
    
    // ====================
    // Serial IO / `debug_clk` domain
    // ====================
    reg[1:0] serialIn_state = 0;
    reg[8:0] serialIn_byte = 0; // High bit is the end-of-data sentinel, and isn't transmitted
    wire serialIn_byteReady = serialIn_byte[8];
    reg[(MsgMaxLen*8)-1:0] serialIn_msg;
    wire[7:0] serialIn_msgType = serialIn_msg[0*8+:8];
    wire[7:0] serialIn_payloadLen = serialIn_msg[1*8+:8];
    reg[7:0] serialIn_payloadCounter = 0;
    reg[1:0] serialOut_state = 0;
    reg[8:0] serialOut_byte = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    assign debug_do = serialOut_byte[8];
    always @(posedge debug_clk) begin
        if (serialIn_byteReady) begin
            serialIn_byte <= {1'b1, debug_di};
        end else begin
            serialIn_byte <= (serialIn_byte<<1)|debug_di;
        end
        
        case (serialIn_state)
        0: begin
            // Initialize `serialIn_byte` as if it was originally initialized to 1,
            // so that after the first clock it contains the sentinel and
            // the first bit of data.
            serialIn_byte <= {1'b1, debug_di};
            serialIn_state <= 1;
        end
        
        // if (inq_writeTrigger && !inq_writeOK) begin
        //     // TODO: handle dropped bytes
        // end
        
        1: begin
            inq_writeTrigger <= 0; // Clear from state 3
            if (serialIn_byteReady) begin
                serialIn_msg[0*8+:8] <= serialIn_byte;
                serialIn_state <= 2;
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
            // Initialize `serialOut_byte` as if it was originally initialized to 1,
            // so that after the first clock cycle it contains the sentinel.
            serialOut_byte <= 2'b10;
            serialOut_state <= 3;
        end
        
        1: begin
            serialOut_byte <= serialOut_byte<<1;
            outq_readTrigger <= 0;
            
            // If we successfully read a byte, shift it out
            if (outq_readOK) begin
                serialOut_byte <= {outq_readData, 1'b1}; // Add sentinel to the end
                serialOut_state <= 2;
            
            // Otherwise shift out 2 zero bytes (msgType=Nop, payloadLen=0)
            end else begin
                serialOut_byte <= 1;
                serialOut_state <= 3;
            end
        end
        
        // Continue shifting out a byte
        2: begin
            serialOut_byte <= serialOut_byte<<1;
            if (serialOut_byte[6:0] == 7'b1000000) begin
                outq_readTrigger <= 1;
                serialOut_state <= 1;
            end
        end
        
        // Shift out 2 zero bytes
        3: begin
            serialOut_byte <= serialOut_byte<<1;
            if (serialOut_byte[7:0] == 8'b10000000) begin
                serialOut_byte <= 1;
                serialOut_state <= 2;
            end
        end
        endcase
    end
endmodule





// module PixController #(
//     parameter ExtClkFreq = 12000000,    // Image sensor's external clock frequency
//     parameter ClkFreq = 12000000        // `clk` frequency
// )(
//     input wire          clk,
//
//     output reg          pix_rst_,
//
//     input wire          pix_dclk,
//     input wire[11:0]    pix_d,
//     input wire          pix_fv,
//     input wire          pix_lv,
//
//     output wire         pix_sclk,
//     inout wire          pix_sdata
// );
//     // Clocks() returns the value to store in a counter, such that when
//     // the counter reaches 0, the given time has elapsed.
//     function [63:0] Clocks;
//         input [63:0] t;
//         input [63:0] sub;
//         begin
//             Clocks = (t*ClkFreq)/1000000000;
//             if (Clocks >= sub) Clocks = Clocks-sub;
//             else Clocks = 0;
//         end
//     endfunction
//
//     function [63:0] Max;
//         input [63:0] a;
//         input [63:0] b;
//         Max = (a > b ? a : b);
//     endfunction
//
//     // Clocks for EXTCLK to settle
//     // EXTCLK (the SiTime 12MHz clock) takes up to 150ms to settle,
//     // but ice40 configuration takes 70 ms, so we only need to wait 80 ms.
//     localparam SettleClocks = Clocks(80000000, 0);
//     // Clocks to assert pix_rst_ (1ms)
//     localparam ResetClocks = Clocks(1000000, 0);
//     // Clocks to wait for sensor to initialize (150k EXTCLKs)
//     localparam InitClocks = Clocks(((150000*1000000000)/ExtClkFreq), 0);
//     // Width of `delay`
//     localparam DelayWidth = Max(Max($clog2(SettleClocks+1), $clog2(ResetClocks+1)), $clog2(InitClocks+1));
//
//     reg[1:0] state = 0;
//     reg[DelayWidth-1:0] delay = 0;
//     always @(posedge clk) begin
//         case (state)
//
//         // Wait for EXTCLK to settle
//         0: begin
//             pix_rst_ <= 1;
//             delay <= SettleClocks;
//             state <= 1;
//         end
//
//         // Assert pix_rst_ for ResetClocks (1ms)
//         1: begin
//             if (delay) begin
//                 delay <= delay-1;
//             end else begin
//                 pix_rst_ <= 0;
//                 delay <= ResetClocks;
//                 state <= 2;
//             end
//         end
//
//         // Deassert pix_rst_ and wait InitClocks
//         2: begin
//             if (delay) begin
//                 delay <= delay-1;
//             end else begin
//                 pix_rst_ <= 1;
//                 delay <= InitClocks;
//                 state <= 3;
//             end
//         end
//
//         3: begin
//             // - Write R0x3052 = 0xA114 to configure the internal register initialization process.
//             // - Write R0x304A = 0x0070 to start the internal register initialization process.
//             // - Wait 150,000 EXTCLK periods
//             // - Configure PLL, output, and image settings to desired values.
//             // - Wait 1ms for the PLL to lock.
//             // - Set streaming mode (R0x301A[2] = 1).
//         end
//         endcase
//     end
// endmodule



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
    
    input wire          debug_clk,
    input wire          debug_di,
    output wire         debug_do
);
    // ====================
    // Clock PLL (54.750 MHz)
    // ====================
    localparam ClockFrequency = 54750000;
    wire clk;
    ClockGen #(
        .FREQ(ClockFrequency),
        .DIVR(0),
        .DIVF(72),
        .DIVQ(4),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));






    //
    // // ====================
    // // SDRAM controller
    // // ====================
    // localparam RAM_Size = 'h2000000;
    // localparam RAM_AddrWidth = 25;
    // localparam RAM_DataWidth = 16;
    //
    // // RAM controller
    // wire                    ram_cmdReady;
    // reg                     ram_cmdTrigger = 0;
    // reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    // reg                     ram_cmdWrite = 0;
    // reg[RAM_DataWidth-1:0]  ram_cmdWriteData = 0;
    // wire[RAM_DataWidth-1:0] ram_cmdReadData;
    // wire                    ram_cmdReadDataValid;
    //
    // SDRAMController #(
    //     .ClockFrequency(ClockFrequency)
    // ) sdramController(
    //     .clk(clk),
    //
    //     .cmdReady(ram_cmdReady),
    //     .cmdTrigger(ram_cmdTrigger),
    //     .cmdAddr(ram_cmdAddr),
    //     .cmdWrite(ram_cmdWrite),
    //     .cmdWriteData(ram_cmdWriteData),
    //     .cmdReadData(ram_cmdReadData),
    //     .cmdReadDataValid(ram_cmdReadDataValid),
    //
    //     .ram_clk(ram_clk),
    //     .ram_cke(ram_cke),
    //     .ram_ba(ram_ba),
    //     .ram_a(ram_a),
    //     .ram_cs_(ram_cs_),
    //     .ram_ras_(ram_ras_),
    //     .ram_cas_(ram_cas_),
    //     .ram_we_(ram_we_),
    //     .ram_dqm(ram_dqm),
    //     .ram_dq(ram_dq)
    // );












    // ====================
    // Debug I/O
    // ====================
    localparam MsgType_Nop              = 8'h00;
    localparam MsgType_SetLED           = 8'h01;
    localparam MsgType_ReadMem          = 8'h02;
    localparam MsgType_PixReadReg8      = 8'h03;
    localparam MsgType_PixReadReg16     = 8'h04;
    localparam MsgType_PixWriteReg8     = 8'h05;
    localparam MsgType_PixWriteReg16    = 8'h06;
    
    wire[(6*8)-1:0] debug_msgIn_data;
    wire debug_msgIn_ready;
    reg debug_msgIn_trigger = 0;
    
    reg[7:0] debug_msgOut_type = 0;
    reg[7:0] debug_msgOut_payloadLen = 0;
    reg[7:0] debug_msgOut_payload = 0;
    reg debug_msgOut_payloadTrigger;
    Debug debug(
        .clk(clk),
        
        .msgIn_data(debug_msgIn_data),
        .msgIn_ready(debug_msgIn_ready),
        .msgIn_trigger(debug_msgIn_trigger),
        
        .msgOut_type(debug_msgOut_type),
        .msgOut_payloadLen(debug_msgOut_payloadLen),
        .msgOut_payload(debug_msgOut_payload),
        .msgOut_payloadTrigger(debug_msgOut_payloadTrigger),
        
        .debug_clk(debug_clk),
        .debug_di(debug_di),
        .debug_do(debug_do)
    );
    
    // ====================
    // Main
    // ====================
    // function [15:0] DataFromAddr;
    //     input [24:0] addr;
    //     // DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
    //     DataFromAddr = addr[15:0];
    //     // DataFromAddr = 16'hFFFF;
    //     // DataFromAddr = 16'h0000;
    //     // DataFromAddr = 16'h7832;
    // endfunction
    //
    // function [63:0] Min;
    //     input [63:0] a;
    //     input [63:0] b;
    //     Min = (a < b ? a : b);
    // endfunction
    
    reg[3:0] state = 0;
    reg[7:0] msgInType = 0;
    reg[4*8-1:0] msgInPayload = 0;
    reg[7:0] mem[255:0];
    reg[7:0] memLen = 0;
    reg[7:0] memCounter = 0;
    reg[7:0] memCounterRecv = 0;
    always @(posedge clk) begin
        case (state)
        
        // Initialize the SDRAM
        0: begin
            // if (!ram_cmdTrigger) begin
            //     ram_cmdTrigger <= 1;
            //     ram_cmdAddr <= 0;
            //     ram_cmdWrite <= 1;
            //     ram_cmdWriteData <= DataFromAddr(0);
            //
            // end else if (ram_cmdReady) begin
            //     ram_cmdAddr <= ram_cmdAddr+1;
            //     ram_cmdWriteData <= DataFromAddr(ram_cmdAddr+1);
            //
            //     if (ram_cmdAddr == RAM_Size-1) begin
            //         ram_cmdTrigger <= 0;
            //         state <= 1;
            //     end
            // end
            
            state <= 1;
        end
        
        // Accept new command
        1: begin
            debug_msgIn_trigger <= 1;
            if (debug_msgIn_trigger && debug_msgIn_ready) begin
                debug_msgIn_trigger <= 0;
                
                msgInType <= debug_msgIn_data[0*8+:8];
                msgInPayload <= debug_msgIn_data[2*8+:4*8];
                
                state <= 2;
            end
        end
        
        // Handle new command
        2: begin
            // By default go to state 3 next
            state <= 3;
            
            case (msgInType)
            default: begin
                debug_msgOut_type <= msgInType;
                debug_msgOut_payloadLen <= 255;
                debug_msgOut_payload <= 0;
            end
            
            MsgType_SetLED: begin
                $display("Set LED: %0d", msgInPayload[0]);
                led[0] <= msgInPayload[0];
                
                debug_msgOut_type <= msgInType;
                debug_msgOut_payloadLen <= 255;
                debug_msgOut_payload <= 0;
            end
            
            // CmdReadMem: begin
            //     ram_cmdAddr <= 0;
            //     ram_cmdWrite <= 0;
            //     state <= 4;
            // end
            
            MsgType_PixReadReg8: begin
                debug_msgOut_type <= msgInType;
                debug_msgOut_payloadLen <= 255;
                debug_msgOut_payload <= 0;
            end
            
            MsgType_PixReadReg16: begin
                debug_msgOut_type <= msgInType;
                debug_msgOut_payloadLen <= 255;
                debug_msgOut_payload <= 0;
            end
            
            MsgType_PixWriteReg8: begin
                debug_msgOut_type <= msgInType;
                debug_msgOut_payloadLen <= 255;
                debug_msgOut_payload <= 0;
            end
            
            MsgType_PixWriteReg16: begin
                debug_msgOut_type <= msgInType;
                debug_msgOut_payloadLen <= 255;
                debug_msgOut_payload <= 0;
            end
            endcase
        end
        
        // Wait while the message is being sent
        3: begin
            if (debug_msgOut_payloadTrigger) begin
                if (debug_msgOut_payloadLen) begin
                    debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                    debug_msgOut_payload <= debug_msgOut_payload+1;
                end else begin
                    state <= 1;
                end
            end
        end
        
        // // Start reading memory
        // 4: begin
        //     ram_cmdTrigger <= 1;
        //     memCounter <= Min(8'h7F, RAM_Size-ram_cmdAddr);
        //     memCounterRecv <= Min(8'h7F, RAM_Size-ram_cmdAddr);
        //     memLen <= 8'h00;
        //     state <= 5;
        // end
        //
        // // Continue reading memory
        // 5: begin
        //     // Handle the read being accepted
        //     if (ram_cmdReady && memCounter) begin
        //         ram_cmdAddr <= (ram_cmdAddr+1)&(RAM_Size-1); // Prevent ram_cmdAddr from overflowing
        //         memCounter <= memCounter-1;
        //
        //         // Stop reading
        //         if (memCounter == 1) begin
        //             ram_cmdTrigger <= 0;
        //         end
        //     end
        //
        //     // Writing incoming data into `mem`
        //     if (ram_cmdReadDataValid) begin
        //         mem[memLen] <= ram_cmdReadData[7:0];
        //         mem[memLen+1] <= ram_cmdReadData[15:8];
        //         memLen <= memLen+2;
        //         memCounterRecv <= memCounterRecv-1;
        //
        //         // Next state after we've received all the bytes
        //         if (memCounterRecv == 1) begin
        //             state <= 6;
        //         end
        //     end
        // end
        //
        // // Start sending the data
        // 6: begin
        //     debug_msg <= CmdReadMem;
        //     debug_msgLen <= memLen+1;
        //     memCounter <= 0;
        //     state <= 7;
        // end
        //
        // // Send the data
        // 7: begin
        //     // Continue sending data
        //     if (debug_msgTrigger) begin
        //         if (debug_msgLen) begin
        //             debug_msg <= mem[memCounter];
        //             debug_msgLen <= debug_msgLen-1;
        //             memCounter <= memCounter+1;
        //         end else begin
        //             // We're finished with this chunk.
        //             // Start on the next chunk, or stop if we've read everything.
        //             if (ram_cmdAddr == 0) begin
        //                 state <= 1;
        //             end else begin
        //                 state <= 4;
        //             end
        //         end
        //     end
        // end
        endcase
    end
    
    
`ifdef SIM
    reg sim_debug_clk = 0;
    reg[7:0] sim_debug_di_shiftReg = 0;
    
    assign debug_clk = sim_debug_clk;
    assign debug_di = sim_debug_di_shiftReg[7];
    // assign debug_di = 1;
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
        
        // Wait for ClockGen to start its clock
        wait(clk);
        #100;
        
        wait (!sim_debug_clk);


        sim_debug_di_shiftReg = MsgType_SetLED;
        repeat (8) begin
            wait (sim_debug_clk);
            wait (!sim_debug_clk);
            sim_debug_di_shiftReg = sim_debug_di_shiftReg<<1;
        end

        sim_debug_di_shiftReg = 1;
        repeat (8) begin
            wait (sim_debug_clk);
            wait (!sim_debug_clk);
            sim_debug_di_shiftReg = sim_debug_di_shiftReg<<1;
        end
        
        sim_debug_di_shiftReg = 1;
        repeat (8) begin
            wait (sim_debug_clk);
            wait (!sim_debug_clk);
            sim_debug_di_shiftReg = sim_debug_di_shiftReg<<1;
        end
        
        #10000;
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

`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../AFIFO.v"
`include "../SDRAMController.v"

module Debug(
    input wire              clk,
    
    output reg[7:0]         msgIn[5:0] = 0,
    output reg              msgIn_ready = 0,
    input wire              msgIn_trigger,
    
    input wire[7:0]         msgOut,
    input wire[8:0]         msgOut_len,
    output reg              msgOut_trigger = 0,
    
    input wire              debug_clk,
    input wire              debug_cs,
    input wire              debug_di,
    output wire             debug_do
);
    localparam MaxPayloadLen = 4; // Max payload length (bytes)
    localparam MaxMsgLen = 2+MaxPayloadLen; // Max message length (bytes)
    
    // ====================
    // In queue `inq`
    // ====================
    AFIFO #(.Width(MaxMsgLen*8), .Size(8)) inq(
        .rclk(clk),
        .r(),
        .rd(),
        .rok(),
        
        .wclk(debug_clk),
        .w(),
        .wd(),
        .wok()
    );
    
    // ====================
    // Out queue `outq`
    // ====================
    AFIFO #(.Width(8), .Size(8)) outq(
        .rclk(debug_clk),
        .r(),
        .rd(),
        .rok(),
        
        .wclk(clk),
        .w(),
        .wd(),
        .wok()
    );
    
    // ====================
    // Command+response handling
    // ====================
    reg[1:0] msgState = 0;
    always @(posedge clk) begin
        case (msgState)
        // Send command (byte 0)
        0: begin
            msg_trigger <= 0; // Necessary to clear the final msg_trigger=1 from state 2
            if (msg_len) begin
                outq_writeData <= msg;
                outq_writeTrigger <= 1;
                msgState <= 1;
            end
        end
        
        // Send message length (byte 1)
        1: begin
            if (outq_writeOK) begin
                outq_writeData <= msg_len-1;
                outq_writeTrigger <= 1;
                msg_trigger <= 1;
                msgState <= 2;
            end
        end
        
        // Delay state while the next message byte is triggered
        2: begin
            msg_trigger <= 0;
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
                msgState <= 3;
            end
        end
        
        // Send the message payload
        3: begin
            if (msg_len) begin
                outq_writeData <= msg;
                outq_writeTrigger <= 1;
                msg_trigger <= 1;
                msgState <= 2;
            end else begin
                msg_trigger <= 1;
                msgState <= 0;
            end
        end
        endcase
    end
    
    
    
    
    
    
    
    
    
    // ====================
    // Data relay/shifting (debug_di->inq, outq->debug_do)
    // ====================
    reg[1:0] in_state = 0;
    reg[1:0] in_substate = 0;
    reg[8:0] in_shiftReg = 0; // High bit is the end-of-data sentinel, and isn't transmitted
    reg[7:0] in_msgType = 0;
    reg[7:0] in_payloadLen = 0;
    reg[7:0] in_payloadCounter = 0;
    reg[7:0] in_len = 0;
    reg[1:0] out_state = 0;
    reg[8:0] out_shiftReg = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    assign debug_do = out_shiftReg[8];
    always @(posedge debug_clk) begin
        if (debug_cs) begin
            case (in_state)
            0: begin
                // Initialize `in_shiftReg` as if it was originally initialized to 1,
                // so that after the first clock it contains the sentinel and
                // the first bit of data.
                in_shiftReg <= {1'b1, debug_di};
                in_state <= 1;
            end
            
            // if (inq_writeTrigger && !inq_writeOK) begin
            //     // TODO: handle dropped bytes
            // end
            
            
            1: begin
                if (in_shiftReg[8]) begin
                    in_shiftReg <= {1'b1, debug_di};
                    
                    case (in_substate)
                    0: begin
                        in_msgType <= in_shiftReg[7:0];
                        in_substate <= 1;
                    end
                    
                    1: begin
                        wire payloadLen = in_shiftReg[7:0];
                        // TODO: handle payloadLen>MaxPayloadLen
                        if (in_msgType) begin
                            if (payloadLen) begin
                                
                            end else begin
                                
                            end
                        
                        end else begin
                            // Nop -- ignore
                            in_substate <= 0;
                        end
                        if (in_msgType && payloadLen<=MaxPayloadLen) begin
                            if ()
                            in_payloadLen <= payloadLen;
                            in_substate <= 2;
                        end
                    end
                    
                    2: begin
                        
                    end
                    endcase
                    
                    
                    // inq_writeTrigger <= 1;
                    // inq_writeData <= in_shiftReg[7:0];
                end else begin
                    // inq_writeTrigger <= 0;
                    in_shiftReg <= (in_shiftReg<<1)|debug_di;
                end
            end
            endcase
            
            case (out_state)
            0: begin
                // Initialize `out_shiftReg` as if it was originally initialized to 1,
                // so that after the first clock cycle it contains the sentinel.
                out_shiftReg <= 2'b10;
                out_state <= 3;
            end
            
            1: begin
                out_shiftReg <= out_shiftReg<<1;
                outq_readTrigger <= 0;
                
                // If we successfully read a byte, shift it out
                if (outq_readOK) begin
                    out_shiftReg <= {outq_readData, 1'b1}; // Add sentinel to the end
                    out_state <= 2;
                
                // Otherwise shift out 2 zero bytes (cmd=Nop, payloadLen=0)
                end else begin
                    out_shiftReg <= 1;
                    out_state <= 3;
                end
            end
            
            // Continue shifting out a byte
            2: begin
                out_shiftReg <= out_shiftReg<<1;
                if (out_shiftReg[6:0] == 7'b1000000) begin
                    outq_readTrigger <= 1;
                    out_state <= 1;
                end
            end
            
            // Shift out 2 zero bytes
            3: begin
                out_shiftReg <= out_shiftReg<<1;
                if (out_shiftReg[7:0] == 8'b10000000) begin
                    out_shiftReg <= 1;
                    out_state <= 2;
                end
            end
            endcase
        end
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
    input wire          debug_cs,
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
    
    
    
    
    
    
    
    // ====================
    // SDRAM controller
    // ====================
    localparam RAM_Size = 'h2000000;
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;

    // RAM controller
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  ram_cmdWriteData = 0;
    wire[RAM_DataWidth-1:0] ram_cmdReadData;
    wire                    ram_cmdReadDataValid;

    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),

        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(ram_cmdReadData),
        .cmdReadDataValid(ram_cmdReadDataValid),

        .ram_clk(ram_clk),
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
    // Debug I/O
    // ====================
    localparam CmdNop       = 8'h00;
    localparam CmdLEDOff    = 8'h80;
    localparam CmdLEDOn     = 8'h81;
    localparam CmdReadMem   = 8'h82;
    
    wire[7:0] debug_cmd;
    wire debug_cmdReady;
    reg debug_cmdTrigger = 0;
    
    reg[7:0] debug_msg = 0;
    reg[8:0] debug_msgLen = 0;
    wire debug_msgTrigger;
    
    Debug debug(
        .clk(clk),
        
        .cmd(debug_cmd),
        .cmdReady(debug_cmdReady),
        .cmdTrigger(debug_cmdTrigger),
        
        .msg(debug_msg),
        .msgLen(debug_msgLen),
        .msgTrigger(debug_msgTrigger),
        
        .debug_clk(debug_clk),
        .debug_cs(debug_cs),
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
    endfunction
    
    function [63:0] Min;
        input [63:0] a;
        input [63:0] b;
        Min = (a < b ? a : b);
    endfunction
    
    reg[3:0] state = 0;
    reg[7:0] mem[255:0];
    reg[7:0] memLen = 0;
    reg[7:0] memCounter = 0;
    reg[7:0] memCounterRecv = 0;
    
    reg[7:0] cmd = CmdNop;
    always @(posedge clk) begin
        case (state)
        
        // Initialize the SDRAM
        0: begin
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
                    state <= 1;
                end
            end
        end
        
        // Accept new command
        1: begin
            debug_cmdTrigger <= 1;
            if (debug_cmdTrigger && debug_cmdReady) begin
                debug_cmdTrigger <= 0;
                cmd <= debug_cmd;
                state <= 2;
            end
        end
        
        // Handle new command
        2: begin
            // By default go to state 3 next
            state <= 3;
            
            case (cmd)
            default: begin
                debug_msg <= cmd;
                debug_msgLen <= 255;
            end
            
            CmdLEDOff: begin
                led[0] <= 0;
                debug_msg <= cmd;
                debug_msgLen <= 255;
            end
            
            CmdLEDOn: begin
                led[0] <= 1;
                debug_msg <= cmd;
                debug_msgLen <= 255;
            end
            
            CmdReadMem: begin
                ram_cmdAddr <= 0;
                ram_cmdWrite <= 0;
                state <= 4;
            end
            endcase
        end
        
        // Wait while the message is being sent
        3: begin
            if (debug_msgTrigger) begin
                if (debug_msgLen) begin
                    debug_msg <= 8'hff-debug_msgLen+1;
                    debug_msgLen <= debug_msgLen-1;
                end else begin
                    state <= 1;
                end
            end
        end
        
        // Start reading memory
        4: begin
            ram_cmdTrigger <= 1;
            memCounter <= Min(8'h7F, RAM_Size-ram_cmdAddr);
            memCounterRecv <= Min(8'h7F, RAM_Size-ram_cmdAddr);
            memLen <= 8'h00;
            state <= 5;
        end
        
        // Continue reading memory
        5: begin
            // Handle the read being accepted
            if (ram_cmdReady && memCounter) begin
                ram_cmdAddr <= (ram_cmdAddr+1)&(RAM_Size-1); // Prevent ram_cmdAddr from overflowing
                memCounter <= memCounter-1;
                
                // Stop reading
                if (memCounter == 1) begin
                    ram_cmdTrigger <= 0;
                end
            end
            
            // Writing incoming data into `mem`
            if (ram_cmdReadDataValid) begin
                mem[memLen] <= ram_cmdReadData[7:0];
                mem[memLen+1] <= ram_cmdReadData[15:8];
                memLen <= memLen+2;
                memCounterRecv <= memCounterRecv-1;
                
                // Next state after we've received all the bytes
                if (memCounterRecv == 1) begin
                    state <= 6;
                end
            end
        end
        
        // Start sending the data
        6: begin
            debug_msg <= CmdReadMem;
            debug_msgLen <= memLen+1;
            memCounter <= 0;
            state <= 7;
        end
        
        // Send the data
        7: begin
            // Continue sending data
            if (debug_msgTrigger) begin
                if (debug_msgLen) begin
                    debug_msg <= mem[memCounter];
                    debug_msgLen <= debug_msgLen-1;
                    memCounter <= memCounter+1;
                end else begin
                    // We're finished with this chunk.
                    // Start on the next chunk, or stop if we've read everything.
                    if (ram_cmdAddr == 0) begin
                        state <= 1;
                    end else begin
                        state <= 4;
                    end
                end
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
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
        
        // Wait for ClockGen to start its clock
        wait(clk);
        #100;
        
        wait (!sim_debug_clk);
        sim_debug_cs = 1;
        sim_debug_di_shiftReg = CmdLEDOn;
        
        repeat (8) begin
            wait (sim_debug_clk);
            wait (!sim_debug_clk);
            sim_debug_di_shiftReg = sim_debug_di_shiftReg<<1;
        end
        
        #1000000;
        $finish;
    end
    
    initial begin
        forever begin
            sim_debug_clk = 0;
            #10;
            sim_debug_clk = 1;
            #10;
        end
    end
`endif
    
endmodule

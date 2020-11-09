`include "../Util/Util.v"
`include "../Util/RAMController.v"
`include "../Util/Delay.v"

`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

module Random6(
    input wire clk, next,
    output reg[5:0] q = 0
);
    always @(posedge clk)
        if (q == 0) q <= 1;
        // Feedback polynomial for N=6: x^6 + x^5 + 1
        else if (next) q <= {q[4:0], q[6-1] ^ q[5-1]};
endmodule

module Random16(
    input wire clk, next,
    output reg[15:0] q = 0
);
    always @(posedge clk)
        if (q == 0) q <= 1;
        // Feedback polynomial for N=16: x^16 + x^15 + x^13 + x^4 + 1
        else if (next) q <= {q[14:0], q[16-1] ^ q[15-1] ^ q[13-1] ^ q[4-1]};
endmodule

module Random25(
    input wire clk, next,
    output reg[24:0] q = 0,
    output reg wrapped
);
    always @(posedge clk)
        if (q == 0) begin
            q <= 1;
            wrapped <= 0;
        end
        // Feedback polynomial for N=25: x^25 + x^22 + 1
        else if (next) begin
            q <= {q[23:0], q[25-1] ^ q[22-1]};
            if (q == 1) wrapped <= !wrapped;
        end
endmodule

module Top(
    input wire          clk24mhz,
    
    output wire[3:0]    led,
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
);
    localparam BlockWidth = 21;
    localparam BlockSize = 16;
    localparam WordIdxWidth = $clog2(BlockSize);
`ifdef SIM
    localparam BlockLimit = 'h100;
`else
    localparam BlockLimit = {BlockWidth{1'b1}};
`endif
    
    function[15:0] DataFromBlockAndWordIdx;
        input[BlockWidth-1:0] block;
        input[WordIdxWidth-1:0] wordIdx;
        DataFromBlockAndWordIdx = {7'h55, wordIdx, block[20:16]} ^ ~(block[15:0]);
    endfunction
    
    function[63:0] Min;
        input[63:0] a;
        input[63:0] b;
        Min = (a < b ? a : b);
    endfunction
    
    wire clk = clk24mhz;
    wire cmd_ready;
    reg cmd_trigger = 0;
    reg[BlockWidth-1:0] cmd_block = 0;
    reg cmd_write = 0;
    wire data_ready;
    reg data_trigger = 0;
    wire[15:0] data_write;
    wire[15:0] data_read;
    
    RAMController #(
        .ClkFreq(24000000),
        .BlockSize(BlockSize)
        // .BlockSize(2304*1296)
    ) RAMCtrl(
        .clk(clk),
        
        .cmd_ready(cmd_ready),
        .cmd_trigger(cmd_trigger),
        .cmd_block(cmd_block),
        .cmd_write(cmd_write),
        
        .data_ready(data_ready),
        .data_trigger(data_trigger),
        .data_write(data_write),
        .data_read(data_read),
        
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
    
    
    
    
    // TODO: add pauses when reading/writing
    // TODO: add a WriteAll mode?
    
    wire wrapped;
    assign led[3] = wrapped;
    
    wire[15:0] random16;
    reg random16Next = 0;
    Random16 random16Gen(.clk(clk), .next(random16Next), .q(random16));
    
    wire[24:0] random25;
    reg random25Next = 0;
    Random25 random25Gen(.clk(clk), .next(random25Next), .q(random25), .wrapped(wrapped));
    wire[BlockWidth-1:0] random25_block = random25&(BlockLimit-1);
    
    wire[5:0] random6;
    reg random6Next = 0;
    Random6 random6Gen(.clk(clk), .next(random6Next), .q(random6));
    wire[5:0] random6_blockCount = Min(BlockLimit-random25_block, random6);
    
    
    reg[4:0] state = 0;
    reg[WordIdxWidth-1:0] wordIdx = 0;
    wire[15:0] data_read_expected = DataFromBlockAndWordIdx(cmd_block, wordIdx);
    reg[5:0] blockCount = 0;
    assign data_write = DataFromBlockAndWordIdx(cmd_block, wordIdx);
    
    always @(posedge clk) begin
        case (state)
        // ====================
        // Initialize Memory
        // ====================
        0: begin
            cmd_trigger <= 1;
            cmd_write <= 1;
            if (cmd_ready && cmd_trigger) begin
                $display("Initializing block %h", cmd_block);
                cmd_trigger <= 0;
                state <= 1;
            end
        end
        
        1: begin
            data_trigger <= 1;
            if (data_ready && data_trigger) begin
                wordIdx <= wordIdx+1;
            end
            
            if (cmd_ready) begin
                data_trigger <= 0;
                if (cmd_block === BlockLimit-1) begin
                    // Finished initializing every block
                    state <= 2;
                end else begin
                    // Next block
                    cmd_block <= cmd_block+1;
                    state <= 0;
                end
            end
        end
        
        2: begin
            // Nop
            if (random16 < 1*'h3333) $display("Nop");
            // Read
            else if (random16 < 2*'h3333)       state <= 3;
            // ReadSeq
            else if (random16 < 3*'h3333)       state <= 6;
            // ReadAll (we want this to be rare so only check for 1 value)
            else if (random16 < 3*'h3333+'h1)   state <= 10;
            // Write
            else if (random16 < 4*'h3333)       state <= 14;
            // WriteSeq
            else                                state <= 17;
            random16Next <= 1;
        end
        
        // ====================
        // Read
        // ====================
        3: begin
            $display("Mode: Read: %h", random25_block);
            cmd_trigger <= 1;
            cmd_write <= 0;
            cmd_block <= random25_block;
            wordIdx <= 0;
            random25Next <= 1;
            state <= 4;
        end
        
        4: begin
            if (cmd_ready) begin
                cmd_trigger <= 0;
                state <= 5;
            end
        end
        
        5: begin
            data_trigger <= 1;
            if (data_ready && data_trigger) begin
                if (data_read === data_read_expected) begin
                    $display("Read word %h[%h]: %h (expected: %h) ✅", cmd_block, wordIdx, data_read, data_read_expected);
                end else begin
                    $display("Read word %h[%h]: %h (expected: %h) ❌", cmd_block, wordIdx, data_read, data_read_expected);
                    `Finish;
                end
                wordIdx <= wordIdx+1;
            end
            
            if (cmd_ready) begin
                data_trigger <= 0;
                state <= 2;
            end
        end
        
        // ====================
        // ReadSeq
        // ====================
        6: begin
            $display("Mode: ReadSeq: %h-%h", random25_block, random25_block+random6_blockCount-1'b1);
            cmd_write <= 0;
            cmd_block <= random25_block;
            blockCount <= random6_blockCount;
            random6Next <= 1;
            random25Next <= 1;
            state <= 7;
        end
        
        7: begin
            if (blockCount) begin
                cmd_trigger <= 1;
                wordIdx <= 0;
                state <= 8;
            
            end else begin
                state <= 2;
            end
        end
        
        8: begin
            if (cmd_ready) begin
                cmd_trigger <= 0;
                state <= 9;
            end
        end
        
        9: begin
            data_trigger <= 1;
            if (data_ready && data_trigger) begin
                if (data_read === data_read_expected) begin
                    $display("Read word %h[%h]: %h (expected: %h) ✅", cmd_block, wordIdx, data_read, data_read_expected);
                end else begin
                    $display("Read word %h[%h]: %h (expected: %h) ❌", cmd_block, wordIdx, data_read, data_read_expected);
                    `Finish;
                end
                wordIdx <= wordIdx+1;
            end
            
            if (cmd_ready) begin
                data_trigger <= 0;
                cmd_block <= cmd_block+1;
                blockCount <= blockCount-1;
                state <= 7;
            end
        end
        
        // ====================
        // ReadAll
        // ====================
        10: begin
            $display("Mode: ReadAll");
            cmd_write <= 0;
            cmd_block <= 0;
            blockCount <= BlockLimit;
            state <= 11;
        end
        
        11: begin
            if (blockCount) begin
                cmd_trigger <= 1;
                wordIdx <= 0;
                state <= 12;
            
            end else begin
                state <= 2;
            end
        end
        
        12: begin
            if (cmd_ready) begin
                cmd_trigger <= 0;
                state <= 13;
            end
        end
        
        13: begin
            data_trigger <= 1;
            if (data_ready && data_trigger) begin
                if (data_read === data_read_expected) begin
                    $display("Read word %h[%h]: %h (expected: %h) ✅", cmd_block, wordIdx, data_read, data_read_expected);
                end else begin
                    $display("Read word %h[%h]: %h (expected: %h) ❌", cmd_block, wordIdx, data_read, data_read_expected);
                    `Finish;
                end
                wordIdx <= wordIdx+1;
            end
            
            if (cmd_ready) begin
                data_trigger <= 0;
                cmd_block <= cmd_block+1;
                blockCount <= blockCount-1;
                state <= 11;
            end
        end
        
        // ====================
        // Write
        // ====================
        14: begin
            $display("Mode: Write: %h", random25_block);
            cmd_trigger <= 1;
            cmd_write <= 1;
            cmd_block <= random25_block;
            wordIdx <= 0;
            random25Next <= 1;
            state <= 15;
        end
        
        15: begin
            if (cmd_ready) begin
                cmd_trigger <= 0;
                state <= 16;
            end
        end
        
        16: begin
            data_trigger <= 1;
            if (data_ready && data_trigger) begin
                // $display("Write word: %h[%h] = %h", cmd_block, wordIdx, data_write);
                wordIdx <= wordIdx+1;
            end
            
            if (cmd_ready) begin
                data_trigger <= 0;
                state <= 2;
            end
        end
        
        // ====================
        // WriteSeq
        // ====================
        17: begin
            $display("Mode: WriteSeq: %h-%h", random25_block, random25_block+random6_blockCount-1'b1);
            cmd_write <= 1;
            cmd_block <= random25_block;
            blockCount <= random6_blockCount;
            random6Next <= 1;
            random25Next <= 1;
            state <= 18;
        end
        
        18: begin
            if (blockCount) begin
                cmd_trigger <= 1;
                wordIdx <= 0;
                state <= 19;
            
            end else begin
                state <= 2;
            end
        end
        
        19: begin
            if (cmd_ready) begin
                cmd_trigger <= 0;
                state <= 20;
            end
        end
        
        20: begin
            data_trigger <= 1;
            if (data_ready && data_trigger) begin
                // $display("Write word: %h[%h] = %h", cmd_block, wordIdx, data_write);
                wordIdx <= wordIdx+1;
            end
            
            if (cmd_ready) begin
                data_trigger <= 0;
                cmd_block <= cmd_block+1;
                blockCount <= blockCount-1;
                state <= 18;
            end
        end
        endcase
    end
    
    
    
    
    
//     reg init = 0;
//     reg status = StatusOK;
//     assign led[0] = status;
//
//     reg[(AddrWidth*MaxEnqueuedReads)-1:0] enqueuedReadAddrs = 0, nextEnqueuedReadAddrs = 0;
//     reg[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount = 0, nextEnqueuedReadCount = 0;
//
//     wire[AddrWidth-1:0] currentReadAddr = enqueuedReadAddrs[AddrWidth-1:0];
//
//     reg[1:0] mode = ModeIdle;
//     reg[AddrWidth-1:0] modeCounter = 0;
//
//     wire[5:0] random6;
//     reg random6Next = 0;
//     Random6 random6Gen(.clk(clk), .next(random6Next), .q(random6));
//
//     wire[15:0] random16;
//     reg random16Next = 0;
//     Random16 random16Gen(.clk(clk), .next(random16Next), .q(random16));
//
//     wire wrapped;
//     assign led[3] = wrapped;
//
//     wire[24:0] random25;
//     wire[24:0] random25Counter;
//     reg random25Next = 0;
//     Random25 random25Gen(.clk(clk), .next(random25Next), .q(random25), .counter(random25Counter), .wrapped(wrapped));
//
//     wire[24:0] randomAddr = random25&(AddrCountLimit-1);
//
//     wire[DataWidth-1:0] expectedReadData = DataFromAddr(currentReadAddr);
//     wire[DataWidth-1:0] prevReadData = DataFromAddr(currentReadAddr-1);
//     wire[DataWidth-1:0] nextReadData = DataFromAddr(currentReadAddr+1);
//
//     always @(posedge clk) begin
//         // Set our default state
//         if (cmd_ready) cmd_trigger <= 0;
//
//         random6Next <= 0;
//         random16Next <= 0;
//         random25Next <= 0;
//
//         // Initialize memory to known values
//         if (!init) begin
//             if (!cmd_write) begin
//                 cmd_trigger <= 1;
//                 cmd_block <= 0;
//                 cmd_write <= 1;
//
//             // The SDRAM controller accepted the command, so transition to the next state
//             end else if (cmd_ready) begin
//                 if (cmd_block < BlockCount-1) begin
// //                if (cmdAddr < 'h7FFFFF) begin
// //                if (cmdAddr < 'hFF) begin
//                     cmd_trigger <= 1;
//                     cmd_block <= cmd_block+1;
//                     cmdWrite <= 1;
//                     cmdWriteData <= DataFromAddr(cmdAddr+1);
//
//                     `ifdef SIM
//                         if (!(cmdAddr % 'h1000)) begin
//                             $display("Initializing memory: %h", cmdAddr);
//                         end
//                     `endif
//
//                 end else begin
//                     // Next stage
//                     init <= 1;
//                 end
//             end
//         end
//
//         else if (status == StatusOK) begin
//             nextEnqueuedReadAddrs = enqueuedReadAddrs;
//             nextEnqueuedReadCount = enqueuedReadCount;
//
//             // Handle read data if available
//             if (cmdReadDataValid) begin
//                 if (nextEnqueuedReadCount > 0) begin
//                     // Verify that the data read out is what we expect
// //                    if ((cmdReadData|1'b1) !== (DataFromAddr(currentReadAddr)|1'b1)) begin
//                     if (cmdReadData !== expectedReadData) begin
//                         `ifdef SIM
//                             $error("Read invalid data; (wanted: 0x%h=0x%h, got: 0x%h=0x%h)", currentReadAddr, DataFromAddr(currentReadAddr), currentReadAddr, cmdReadData);
//                         `endif
//
//                         status <= StatusFailed;
//                         // led[6:0] <= 7'b1111111;
//                     end
//
//                     nextEnqueuedReadAddrs = nextEnqueuedReadAddrs >> AddrWidth;
//                     nextEnqueuedReadCount = nextEnqueuedReadCount-1;
//
//                 // Something's wrong if we weren't expecting data and we got some
//                 end else begin
//                     `ifdef SIM
//                         $error("Received data when we didn't expect any");
//                     `endif
//
//                     status <= StatusFailed;
//                 end
//             end
//
//             // Current command was accepted: prepare a new command
//             if (cmdReady) begin
//                 case (mode)
//                 // We're idle: accept a new mode
//                 ModeIdle: begin
//                     // Nop
//                     if (random16 < 1*'h3333) begin
//                         `ifdef SIM
//                             $display("Nop");
//                         `endif
//                     end
//
//                     // Read
//                     else if (random16 < 2*'h3333) begin
//                         `ifdef SIM
//                             $display("Read: %h", randomAddr);
//                         `endif
//
//                         cmd_trigger <= 1;
//                         cmdAddr <= randomAddr;
//                         cmdWrite <= 0;
//
//                         nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|(randomAddr<<(AddrWidth*nextEnqueuedReadCount));
//                         nextEnqueuedReadCount = nextEnqueuedReadCount+1;
//
//                         mode <= ModeIdle;
//                         random25Next <= 1;
//                     end
//
//                     // Read sequential (start)
//                     else if (random16 < 3*'h3333) begin
//                         `ifdef SIM
//                             $display("ReadSeq: %h[%h]", randomAddr, random6);
//                         `endif
//
//                         cmd_trigger <= 1;
//                         cmdAddr <= randomAddr;
//                         cmdWrite <= 0;
//
//                         nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|(randomAddr<<(AddrWidth*nextEnqueuedReadCount));
//                         nextEnqueuedReadCount = nextEnqueuedReadCount+1;
//
//                         mode <= ModeRead;
//                         modeCounter <= random6;
//                         random6Next <= 1;
//                         random25Next <= 1;
//                     end
//
//                     // Read all (start)
//                     // We want this to be rare so only check for 1 value
//                     else if (random16 < 3*'h3333+'h1) begin
//                         `ifdef SIM
//                             $display("ReadAll");
//                         `endif
//
//                         cmd_trigger <= 1;
//                         cmdAddr <= 0;
//                         cmdWrite <= 0;
//
//                         nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|(0<<(AddrWidth*nextEnqueuedReadCount));
//                         nextEnqueuedReadCount = nextEnqueuedReadCount+1;
//
//                         mode <= ModeRead;
//                         modeCounter <= AddrCountLimit-1;
//                     end
//
//                     // Write
//                     else if (random16 < 4*'h3333) begin
//                         `ifdef SIM
//                             $display("Write: %h", randomAddr);
//                         `endif
//
//                         cmd_trigger <= 1;
//                         cmdAddr <= randomAddr;
//                         cmdWrite <= 1;
//                         cmdWriteData <= DataFromAddr(randomAddr);
//
//                         mode <= ModeIdle;
//                         random25Next <= 1;
//                     end
//
//                     // Write sequential (start)
//                     else begin
//                         `ifdef SIM
//                             $display("WriteSeq: %h[%h]", randomAddr, random6);
//                         `endif
//
//                         cmd_trigger <= 1;
//                         cmdAddr <= randomAddr;
//                         cmdWrite <= 1;
//                         cmdWriteData <= DataFromAddr(randomAddr);
//
//                         mode <= ModeWrite;
//                         modeCounter <= random6;
//                         random6Next <= 1;
//                         random25Next <= 1;
//                     end
//
//                     random16Next <= 1;
//                 end
//
//                 // Read (continue)
//                 ModeRead: begin
//                     if (modeCounter>0 && (cmdAddr+1)<AddrCountLimit) begin
//                         cmd_trigger <= 1;
//                         cmdAddr <= cmdAddr+1;
//                         cmdWrite <= 0;
//
//                         nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|((cmdAddr+1)<<(AddrWidth*nextEnqueuedReadCount));
//                         nextEnqueuedReadCount = nextEnqueuedReadCount+1;
//
//                         modeCounter <= modeCounter-1;
//
//                     end else mode <= ModeIdle;
//                 end
//
//                 // Write (continue)
//                 ModeWrite: begin
//                     if (modeCounter>0 && (cmdAddr+1)<AddrCountLimit) begin
//                         cmd_trigger <= 1;
//                         cmdAddr <= cmdAddr+1;
//                         cmdWrite <= 1;
//                         cmdWriteData <= DataFromAddr(cmdAddr+1);
//
//                         modeCounter <= modeCounter-1;
//
//                     end else mode <= ModeIdle;
//                 end
//                 endcase
//             end
//
//             enqueuedReadAddrs <= nextEnqueuedReadAddrs;
//             enqueuedReadCount <= nextEnqueuedReadCount;
//         end
//     end
    
    
endmodule




`ifdef SIM
module Testbench();
    reg clk24mhz = 0;
    wire[3:0] led;
    wire ram_clk;
    wire ram_cke;
    wire[1:0] ram_ba;
    wire[12:0] ram_a;
    wire ram_cs_;
    wire ram_ras_;
    wire ram_cas_;
    wire ram_we_;
    wire[1:0] ram_dqm;
    wire[15:0] ram_dq;
    Top Top(.*);
    
    mobile_sdr sdram(
        .clk(ram_clk),
        .cke(ram_cke),
        .addr(ram_a),
        .ba(ram_ba),
        .cs_n(ram_cs_),
        .ras_n(ram_ras_),
        .cas_n(ram_cas_),
        .we_n(ram_we_),
        .dq(ram_dq),
        .dqm(ram_dqm)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Testbench);
    end
    
    // initial begin
    //     #10000000;
    //     `Finish;
    // end
    
    initial begin
        forever begin
            clk24mhz = 0;
            #21;
            clk24mhz = 1;
            #21;
        end
    end
endmodule
`endif

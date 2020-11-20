`include "Util.v"
`include "RAMController.v"
`include "Delay.v"

`ifdef SIM
`include "../../mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

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
    wire clk = clk24mhz;
    reg cmd_trigger = 0;
    reg[20:0] cmd_block = 0;
    reg cmd_write = 0;
    wire cmd_done;
    
    wire write_ready;
    reg write_trigger = 0;
    wire[15:0] write_data;
    wire read_ready;
    reg read_trigger = 0;
    wire[15:0] read_data;
    
    localparam BlockSize = 16;
    
    RAMController #(
        .ClkFreq(24000000),
        .BlockSize(BlockSize)
        // .BlockSize(2304*1296)
    ) RAMController(
        .clk(clk),
        
        .cmd_trigger(cmd_trigger),
        .cmd_block(cmd_block),
        .cmd_write(cmd_write),
        .cmd_done(cmd_done),
        
        .write_ready(write_ready),
        .write_trigger(write_trigger),
        .write_data(write_data),
        
        .read_ready(read_ready),
        .read_trigger(read_trigger),
        .read_data(read_data),
        
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
    
    reg[3:0] state = 0;
    reg[$clog2(BlockSize)-1:0] word_idx = 0;
    assign write_data = cmd_block^word_idx;
    wire[15:0] read_data_expected = cmd_block^word_idx;
    reg[7:0] abortCounter = 0;
    
    always @(posedge clk24mhz) begin
        cmd_trigger <= 0;
        write_trigger <= 0;
        read_trigger <= 0;
        case (state)
        0: begin
            $display("Write started @ block %x", cmd_block);
            cmd_trigger <= 1;
            cmd_write <= 1;
            word_idx <= 0;
            state <= 1;
        end
        
        1: begin
            write_trigger <= 1;
            if (write_ready && write_trigger) begin
                $display("Wrote word: %h", write_data);
                word_idx <= word_idx+1;
            end
            
            if (cmd_done) begin
                $display("Write done @ block %x", cmd_block);
                state <= 2;
            end
        end
        
        2: begin
            $display("Read started @ block %x", cmd_block);
            cmd_trigger <= 1;
            cmd_write <= 0;
            word_idx <= 0;
            state <= 3;
        end
        
        3: begin
            read_trigger <= 1;
            if (read_ready && read_trigger) begin
                if (read_data === read_data_expected) begin
                    $display("Read word: %h (expected: %h) ✅", read_data, read_data_expected);
                end else begin
                    $display("Read word: %h (expected: %h) ❌", read_data, read_data_expected);
                    // `Finish;
                end
                word_idx <= word_idx+1;
            end
            
            if (cmd_done) begin
                $display("Read done @ block %x", cmd_block);
                cmd_block <= cmd_block+1;
                state <= 0;
            end
        end
        
        4: begin
            // TODO: randomly switch between aborting to reading and aborting to writing?
            $display("ABORTING");
            state <= 0;
        end
        endcase
        
        abortCounter <= abortCounter+1;
        if (&abortCounter) begin
            state <= 4;
        end
    end
    
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
        $dumpfile("Top.vcd");
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

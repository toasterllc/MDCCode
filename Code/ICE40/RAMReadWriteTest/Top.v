`include "../Util/Util.v"
`include "../Util/RAMController.v"
`include "../Util/Delay.v"

`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
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
    wire cmd_ready;
    reg cmd_trigger = 0;
    reg[20:0] cmd_block = 0;
    reg cmd_write = 0;
    wire data_ready;
    reg data_trigger = 0;
    wire[15:0] data_write;
    wire[15:0] data_read;
    
    localparam BlockSize = 16;
    
    RAMController #(
        .ClkFreq(24000000),
        .BlockSize(BlockSize)
        // .BlockSize(2304*1296)
    ) RAMController(
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
    
    reg[3:0] state = 0;
    reg[$clog2(BlockSize)-1:0] word_idx = 0;
    assign data_write = cmd_block^word_idx;
    // assign data_write = word_idx;
    wire[15:0] data_read_expected = cmd_block^word_idx;
    // wire[15:0] data_read_expected = word_idx;
    
    always @(posedge clk24mhz) begin
        case (state)
        0: begin
            cmd_trigger <= 1;
            cmd_write <= 1;
            word_idx <= 0;
            if (cmd_ready && cmd_trigger) begin
                $display("Write started @ block %h", cmd_block);
                cmd_trigger <= 0;
                state <= 1;
            end
        end
        
        1: begin
            data_trigger <= 1;
            if (data_ready && data_trigger) begin
                // $display("Wrote word: %h", data_write);
                word_idx <= word_idx+1;
            end
            
            if (cmd_ready) begin
                data_trigger <= 0;
                state <= 2;
            end
        end
        
        2: begin
            cmd_trigger <= 1;
            cmd_write <= 0;
            word_idx <= 0;
            if (cmd_ready && cmd_trigger) begin
                $display("Read started");
                cmd_trigger <= 0;
                state <= 3;
            end
        end
        
        3: begin
            data_trigger <= 1;
            if (data_ready && data_trigger) begin
                if (data_read === data_read_expected) begin
                    $display("Read word: %h (expected: %h) ✅", data_read, data_read_expected);
                end else begin
                    $display("Read word: %h (expected: %h) ❌", data_read, data_read_expected);
                    `Finish;
                end
                word_idx <= word_idx+1;
            end
            
            if (cmd_ready) begin
                data_trigger <= 0;
                cmd_block <= cmd_block+1;
                state <= 0;
            end
        end
        endcase
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

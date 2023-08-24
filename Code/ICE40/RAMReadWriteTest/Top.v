`include "Util.v"
`include "RAMController.v"
`include "Delay.v"
`include "ClockGen.v"

`ifdef SIM
`include "mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    output reg[1:0]     ice_led = 0,
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[11:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
);
    // ====================
    // Clock (108 MHz)
    // ====================
    localparam Clk_Freq = 108_000_000;
    wire clk;
    ClockGen #(
        .FREQOUT(Clk_Freq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGe(.clkRef(ice_img_clk16mhz), .clk(clk));
    
    
    reg cmd_trigger = 0;
    reg[18:0] cmd_block = 0;
    reg[1:0] cmd = 0;
    
    wire write_ready;
    reg write_trigger = 0;
    wire[15:0] write_data;
    
    wire read_ready;
    reg read_trigger = 0;
    wire[15:0] read_data;
    
    localparam BlockSize = 16;
    
    RAMController #(
        .ClkFreq(Clk_Freq),
        .RAMClkDelay(0),
        .BlockSize(BlockSize)
        // .BlockSize(2304*1296)
    ) RAMController(
        .clk(clk),
        
        .cmd(cmd),
        .cmd_block(cmd_block),
        
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
    reg[`RegWidth(BlockSize-1)-1:0] word_idx = 0;
    
    assign write_data = cmd_block^word_idx;
    wire[15:0] read_data_expected = cmd_block^word_idx;
    // assign write_data = word_idx;
    // wire[15:0] read_data_expected = word_idx;
    
    reg[9:0] abortCounter = 0;
    
    // initial begin
    //     wait(!clk);
    //     cmd = `RAMController_Cmd_Write;
    //     wait(clk);
    //     wait(!clk);
    //     cmd = `RAMController_Cmd_None;
    //
    //     write_trigger = 1;
    //
    //     // Wait for writing to start
    //     while (!(write_ready && write_trigger)) begin
    //         wait(clk);
    //         wait(!clk);
    //     end
    // end
    
    always @(posedge clk) begin
        cmd <= `RAMController_Cmd_None;
        write_trigger <= 0;
        read_trigger <= 0;
        case (state)
        0: begin
            $display("Write started @ block %x", cmd_block);
            cmd <= `RAMController_Cmd_Write;
            word_idx <= 0;
            state <= 1;
        end
        
        // Wait state for command to be accepted
        1: begin
            state <= 2;
        end
        
        2: begin
            write_trigger <= 1;
            if (write_ready && write_trigger) begin
                $display("Wrote word: %h @ %h", write_data, word_idx);
                word_idx <= word_idx+1;
                
                // Check if we're done writing to this block
                if (&word_idx) begin
                    $display("Write done @ block %x", cmd_block);
                    write_trigger <= 0;
                    state <= 3;
                end
            end
        end
        
        3: begin
            $display("Read started @ block %x", cmd_block);
            cmd <= `RAMController_Cmd_Read;
            word_idx <= 0;
            state <= 4;
        end
        
        // Wait state for command to be accepted
        4: begin
            state <= 5;
        end
        
        5: begin
            read_trigger <= 1;
            if (read_ready && read_trigger) begin
                if (read_data === read_data_expected) begin
                    $display("Read word: %h (expected: %h) ✅", read_data, read_data_expected);
                end else begin
                    $display("Read word: %h (expected: %h) ❌", read_data, read_data_expected);
                    ice_led <= 2'b11;
                    `Finish;
                end
                word_idx <= word_idx+1;
                
                // Check if we're done reading to this block
                if (&word_idx) begin
                    $display("Read done @ block %x", cmd_block);
                    read_trigger <= 0;
                    cmd_block <= cmd_block+1;
                    state <= 0;
                end
            end
        end
        endcase
        
        abortCounter <= abortCounter+1;
        if (&abortCounter) begin
            $display("ABORTING");
            cmd <= `RAMController_Cmd_None;
            write_trigger <= 0;
            read_trigger <= 0;
            cmd_block <= cmd_block+7;
            state <= 0;
        end
    end
    
endmodule




`ifdef SIM
module Testbench();
    reg ice_img_clk16mhz = 0;
    wire[1:0] ice_led;
    wire ram_clk;
    wire ram_cke;
    wire[1:0] ram_ba;
    wire[11:0] ram_a;
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
            #32;
            ice_img_clk16mhz = !ice_img_clk16mhz;
        end
    end
endmodule
`endif

`include "../Util.v"
`include "../ClockGen.v"
`include "../BankFifo.v"
`timescale 1ns/1ps

module Top(
    input wire clk12mhz,
    input wire go,
    output reg[3:0] led = 0
);
    // ====================
    // w_clk
    // ====================
    wire w_clk;
    ClockGen #(
        .FREQ(72000000),
        .DIVR(0),
        .DIVF(47),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_w_clk(.clk12mhz(clk12mhz), .clk(w_clk));

    // ====================
    // r_clk
    // ====================
    wire r_clk;
    ClockGen #(
        .FREQ(48000000),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(4),
        .FILTER_RANGE(1)
    ) ClockGen_r_clk(.clk12mhz(clk12mhz), .clk(r_clk));

    // ====================
    // Writer
    // ====================
    reg[1:0] w_go = 0;
    always @(posedge w_clk)
        w_go <= w_go<<1|go;
    
    reg w_trigger = 0;
    reg[15:0] w_data = 0;
    wire w_done;
    always @(posedge w_clk) begin
        if (w_go[1]) begin
            w_trigger <= 1;
            if (w_done) begin
                w_data <= w_data+1;
            end
        end
    end

    // ====================
    // Reader
    // ====================
    reg[1:0] r_go = 0;
    always @(posedge r_clk)
        r_go <= r_go<<1|go;
    
    reg r_trigger = 0;
    reg[15:0] r_lastData = 0;
    reg[15:0] r_lastData2 = 0;
    reg r_lastDataInit = 0;
    reg r_lastDataInit2 = 0;
    wire[15:0] r_data;
    wire r_done;
    always @(posedge r_clk) begin
        if (r_go[1]) begin
            r_trigger <= 1;
        end
        
        if (r_done) begin
            {r_lastData2, r_lastData} <= {r_lastData, r_data};
            {r_lastDataInit2, r_lastDataInit} <= {r_lastDataInit, 1'b1};
        end
        
        if (r_lastDataInit && r_lastDataInit2) begin
            if (r_lastData !== r_lastData2+2'b01) begin
                $display("Got bad data: %x, %x", r_lastData2, r_lastData);
                led <= 4'b1111;
                `finish;
            
            end else begin
                $display("Got good data: %x", r_lastData2);
            end
        end
    end
    
    // ====================
    // FIFO
    // ====================
    BankFifo BankFifo(
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_done(w_done),
        
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_done(r_done)
    );
endmodule








`ifdef SIM
module Testbench();
    reg clk12mhz = 0;
    reg go = 0;
    wire[3:0] led;
    Top Top(
        .clk12mhz(clk12mhz),
        .go(go),
        .led(led)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Testbench);
    end
    
    initial begin
        go = 0;
        #1000;
        go = 1;
    end
    
    
    // initial begin
    //     reg[15:0] i;
    //     reg[15:0] count;
    //
    //     count = $urandom()%50;
    //     for (i=0; i<count; i=i+1) begin
    //         wait(w_clk);
    //         wait(!w_clk);
    //     end
    //
    //
    //
    //
    //     $display("[WRITER] Writing 128 words");
    //     w_trigger = 1;
    //     w_data = 0;
    //     for (i=0; i<128; i=i+1) begin
    //         wait(w_clk);
    //         wait(!w_clk);
    //         w_data = w_data+1;
    //     end
    //     w_trigger = 0;
    //     $display("[WRITER] Done writing");
    //
    //
    //     $display("[WRITER] Writing 128 words");
    //     w_trigger = 1;
    //     for (i=0; i<128; i=i+1) begin
    //         wait(w_clk);
    //         wait(!w_clk);
    //         w_data = w_data+1;
    //     end
    //     w_trigger = 0;
    //     $display("[WRITER] Done writing");
    //
    //
    //
    //     count = $urandom()%50;
    //     for (i=0; i<count; i=i+1) begin
    //         wait(w_clk);
    //         wait(!w_clk);
    //     end
    // end
endmodule
`endif



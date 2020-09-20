`include "../Util.v"
`include "../ClockGen.v"
`include "../BankFifo.v"
`timescale 1ns/1ps

module Top(
    input wire clk12mhz,
    // output wire[3:0] led,
    output reg err = 0
);
    // ====================
    // w_clk
    // ====================
    wire w_clk;
    ClockGen #(
        .FREQ(120000000),
        .DIVR(0),
        .DIVF(79),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_w_clk(.clk12mhz(clk12mhz), .clk(w_clk));
    
    // ====================
    // r_clk
    // ====================
    wire r_clk;
    ClockGen #(
        .FREQ(120000000),
        .DIVR(0),
        .DIVF(79),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_r_clk(.clk12mhz(clk12mhz), .clk(r_clk));
    
    // ====================
    // Writer
    // ====================
    reg w_trigger = 0;
    reg[15:0] w_data = 0;
    wire w_done;
    
    always @(posedge w_clk) begin
        w_trigger <= 1;
        if (w_done) begin
            w_data <= w_data+1;
        end
    end
    
    // ====================
    // Reader
    // ====================
    
    // reg[9:0] ledReg = 0;
    // always @(posedge clk12mhz) begin
    //     ledReg <= ledReg<<1|err;
    // end
    // assign led[3:0] = {4{err}};
    
    reg r_trigger = 0;
    wire[15:0] r_data;
    wire r_done;
    always @(posedge r_clk) begin
        r_trigger <= 1;
        if (r_done) begin
            if (r_data !== 16'hABCD) begin
                $display("Got bad data: %x", r_data);
                err <= 1;
                `finish;
            end
        end
    end
    
    // ====================
    // FIFO
    // ====================
    BankFifo BankFifo(
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(16'hABCD),
        .w_done(w_done),
        
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_done(r_done)
    );

`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
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
`endif
endmodule

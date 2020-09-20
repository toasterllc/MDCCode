`include "../Util.v"
`include "../ClockGen.v"
`include "../BankFifo.v"
`timescale 1ns/1ps


module Top(
    input wire clk12mhz
);
    reg w_clk;
    reg r_clk;
    
    reg w_trigger = 0;
    reg[15:0] w_data = 0;
    wire w_done;
    
    reg r_trigger = 0;
    wire[15:0] r_data;
    wire r_done;
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
    
    always @(posedge w_clk) begin
        w_trigger <= 1;
        if (w_done) begin
            w_data <= w_data+1;
        end
    end
    
    reg[15:0] r_lastData = 0;
    reg r_lastDataInit = 0;
    always @(posedge r_clk) begin
        r_trigger <= 1;
        if (r_done) begin
            $display("Got data: 0x%x", r_data);
            r_lastDataInit <= 1;
            r_lastData <= r_data;
            
            if (r_lastDataInit && (r_data!==(r_lastData+1'b1))) begin
                $display("Bad data (wanted: %x, got: %x)", r_lastData+1'b1, r_data);
                `finish;
            end
        end
    end

`ifdef SIM
    initial begin
        forever begin
            r_clk = 0;
            #42;
            r_clk = 1;
            #42;
        end
    end
    
    initial begin
        forever begin
            w_clk = 0;
            #21;
            w_clk = 1;
            #21;
        end
    end
    
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

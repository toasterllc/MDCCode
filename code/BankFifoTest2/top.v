`include "../Util.v"
`include "../ClockGen.v"
`include "../BankFifo.v"
`timescale 1ns/1ps

module Top();
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
        .FREQ(96000000),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_r_clk(.clk12mhz(clk12mhz), .clk(r_clk));
    
    // ====================
    // FIFO
    // ====================
    reg w_trigger;
    reg[15:0] w_data = 0;
    wire w_ok;
    reg r_trigger = 0;
    wire[15:0] r_data;
    wire r_ok;
    BankFifo BankFifo(
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_ok(w_ok),
        
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_ok(r_ok)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        reg[15:0] i;
        reg[15:0] count;
        
        
        // // Wait random number of r_clk cycles
        // count = $urandom()%50;
        // for (i=0; i<count; i=i+1) begin
        //     wait(r_clk);
        //     wait(!r_clk);
        // end
        //
        // $display("[READER] Reading until rok=0");
        // r_trigger = 1;
        // for (i=0; r_ok; i=i+1) begin
        //     $display("[READER]  Read %x", r_data);
        //     wait(r_clk);
        //     wait(!r_clk);
        // end
        // r_trigger = 0;
        // $display("[READER] Done reading");
        
        
        
        
        
        // Wait random number of w_clk cycles
        count = $urandom()%50;
        for (i=0; i<count; i=i+1) begin
            wait(w_clk);
            wait(!w_clk);
        end
        
        $display("[WRITER] Writing until wok=0");
        w_trigger = 1;
        for (i=0; w_ok; i=i+1) begin
            wait(w_clk);
            wait(!w_clk);
            $display("[WRITER]  Wrote %x", w_data);
            w_data = w_data+1;
        end
        w_trigger = 0;
        $display("[WRITER] Done writing");
        
        
        
        

        // Wait random number of r_clk cycles
        count = $urandom()%50;
        for (i=0; i<count; i=i+1) begin
            wait(r_clk);
            wait(!r_clk);
        end

        $display("[READER] Reading until rok=0");
        r_trigger = 1;
        for (i=0; r_ok; i=i+1) begin
            $display("[READER]  Read %x", r_data);
            wait(r_clk);
            wait(!r_clk);
        end
        r_trigger = 0;
        $display("[READER] Done reading");










        // Wait random number of w_clk cycles
        count = $urandom()%50;
        for (i=0; i<count; i=i+1) begin
            wait(w_clk);
            wait(!w_clk);
        end

        $display("[WRITER] Writing until wok=0");
        w_trigger = 1;
        for (i=0; w_ok; i=i+1) begin
            wait(w_clk);
            wait(!w_clk);
            $display("[WRITER]  Wrote %x", w_data);
            w_data = w_data+1;
        end
        w_trigger = 0;
        $display("[WRITER] Done writing");
        //
        //
        //
        //
        // // Wait random number of r_clk cycles
        // count = $urandom()%50;
        // for (i=0; i<count; i=i+1) begin
        //     wait(r_clk);
        //     wait(!r_clk);
        // end
        //
        // $display("[READER] Reading until rok=0");
        // r_trigger = 1;
        // for (i=0; r_ok; i=i+1) begin
        //     $display("[READER]  Read %x", r_data);
        //     wait(r_clk);
        //     wait(!r_clk);
        // end
        // r_trigger = 0;
        // $display("[READER] Done reading");
        
        
        
    end
endmodule

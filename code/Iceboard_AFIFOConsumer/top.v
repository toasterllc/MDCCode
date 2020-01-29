`timescale 1ns/1ps
// `include "../ClockGen.v"
`include "../AFIFO.v"
`include "../Icestick_AFIFOProducer/top.v"

module Iceboard_AFIFOConsumer(
    input wire clk12mhz,
    output wire led,
    input wire wclk,
    input wire w,
    input wire[11:0] wd
);
    wire clk;
    wire rst;
    
    // 100 MHz clock
    ClockGen #(
        .FREQ(16),
		.DIVR(0),
		.DIVF(84),
		.DIVQ(6),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst(rst));
    
    
    
    // reg[15:0] wrstShiftReg;
    // wire wrstStart = wrstShiftReg[0];
    // wire wrstDeassert = wrstShiftReg[7];
    // wire wrstDone = wrstShiftReg[15];
    // wire wrst =
    // always @(posedge clk) begin
    //     if (rst) wrstShiftReg <= 1;
    //     else if (wrst) wrstShiftReg <= (wrstShiftReg<<1)|1;
    // end
    
    // wire wclktri;
    // Tristate wclkTristate(.d(clk), .en(wrst), .q(wclktri));
    
    reg wrst;
    always @(negedge clk) begin
        if (rst) wrst <= 1;
        else wrst <= 0;
    end
    
    reg r;
    wire[11:0] rd;
    wire rok;
    AFIFO #(.Size(32)) afifo(
        .rclk(clk),
        .rrst(rst),
        .r(r),
        .rd(rd),
        .rok(rok),
        
        .wclk(wrst ? clk : wclk),
        .wrst(wrst),
        .w(w),
        .wd(wd),
        .wok()
    );
    
    // Consume values
    reg[11:0] rval;
    reg rvalValid;
    reg rfail;
    always @(posedge clk) begin
        if (rst) begin
            r <= 0;
            rvalValid <= 0;
            rfail <= 0;
        
        end else if (!rfail) begin
            // Init
            if (!r) begin
                r <= 1;
            
            // Read if data is available
            end else if (rok) begin
                $display("Read value: %h", rd);
                rval <= rd;
                rvalValid <= 1;
                
                // Check if the current value is the previous value +1
                // `assert(!rvalValid | ((rval+1'b1)==rd));
                if (rvalValid & ((rval+1'b1)!=rd)) begin
                    $display("Error: read invalid value; wanted: %h got: %h", (rval+1'b1), rd);
                    rfail <= 1;
                    // Stop reading
                    r <= 0;
                end
            end
        end
    end
    
    assign led = rfail;
    // assign led = rst;
    // assign led = !rempty;
    // assign led = rvalValid;
    
`ifdef SIM
    Icestick_AFIFOProducer producer(.clk12mhz(clk12mhz), .wclk(wclk), .w(w), .wd(wd));
    
    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, Iceboard_AFIFOConsumer);
       #10000000000000;
       $finish;
      end
`endif
endmodule

`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../AFIFO.v"
// `include "../Icestick_AFIFOProducer/top.v"

module Iceboard_AFIFOConsumer(
    input wire clk12mhz,
    output wire led,
    input wire wclk,
    input wire w,
    input wire[11:0] wd
);
    // 100 MHz clock
    wire clk;
    ClockGen #(
        .FREQ(16),
		.DIVR(0),
		.DIVF(84),
		.DIVQ(6),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst());
    
    
    
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
    
    reg r = 0;
    wire[11:0] rd;
    wire rok;
    AFIFO #(.Size(32)) afifo(
        .rclk(clk),
        .r(r),
        .rd(rd),
        .rok(rok),
        
        .wclk(wclk),
        .w(w),
        .wd(wd),
        .wok()
    );
    
    // Consume values
    reg[11:0] rval1=0, rval2=0;
    reg rval1Valid=0, rval2Valid=0;
    reg rfail = 0 /* synthesis syn_keep=1 */; // syn_keep is necessary to prevent Synplify optimization from removing -- "removing sequential instance ..."
    always @(posedge clk) begin
        if (!rfail) begin
            // Init
            if (!r) begin
                r <= 1;
            
            // Read if data is available
            end else if (rok) begin
                $display("Read value: %h", rd);
                rval2 <= rd;
                rval2Valid <= 1'b1;
                
                rval1 <= rval2;
                rval1Valid <= rval2Valid;
                
                // Check if the current value is the previous value +1
                if ((rval1Valid&rval2Valid) & ((rval1+1'b1)!=rval2)) begin
                    $display("Error: read invalid value; wanted: %h got: %h", (rval1+1'b1), rval2);
                    rfail <= 1;
                end
            end
        end
    end
    
    assign led = rfail;
    
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

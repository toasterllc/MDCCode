`timescale 1ns/1ps
`include "../AFIFO.v"

`ifdef SIM
`include "../Icestick_AFIFOProducer/top.v"
`endif

module Iceboard_AFIFOConsumer(
`ifndef SIM
    input wire clk12mhz,
`endif
    
    output wire led,
    
    input wire wclk,
    input wire w,
    input wire[11:0] wd
);
    
    wire clk;
`ifdef SIM
    reg[7:0] clkDivider = 0;
`else
    reg[11:0] clkDivider = 0;
`endif
    
    always @(posedge clk12mhz) clkDivider <= clkDivider+1;
    assign clk = clkDivider[$size(clkDivider)-1];
    
`ifdef SIM
    // clk12mhz
    reg clk12mhz = 0;
    initial begin
        forever begin
            clk12mhz = !clk12mhz;
            #42; // 12 MHz
        end
    end
    
    Icestick_AFIFOProducer producer(.clk12mhz(clk12mhz), .clk(wclk), .w(w), .wd(wd));
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Iceboard_AFIFOConsumer);
        #100000000;
        $finish;
    end
`endif
    
    // wire wclk;
    // assign wclk = clk;
    
    reg r = 0;
    wire[11:0] rd;
    wire rempty;
    
    AFIFO afifo(
        .rclk(clk),
        .r(r),
        .rd(rd),
        .rempty(rempty),
        
        .wclk(wclk),
        .w(w),
        .wd(wd),
        .wfull()
    );
    
    // Consume values
    reg[11:0] rval;
    reg rvalValid = 0;
    reg rfail = 0;
    always @(posedge clk) begin
        if (!rfail) begin
            // Init
            if (!r) begin
                r <= 1;
            
            // Read if data is available
            end else if (!rempty) begin
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
    // assign led = !rempty;
    // assign led = rvalValid;
endmodule

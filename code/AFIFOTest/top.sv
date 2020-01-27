`timescale 1ns/1ps
`include "../GrayCode.v"

`define stringify(x) `"x```"
`define assert(cond) if (!(cond)) $error("Assertion failed: %s (%s:%0d)", `stringify(cond), `__FILE__, `__LINE__)

module AFIFO(
    input logic rrst_,
    input logic rclk,
    input logic r,
    output logic[Width-1:0] rd,
    output logic rempty,
    
    input logic wrst_,
    input logic wclk,
    input logic w,
    input logic[Width-1:0] wd,
    output logic wfull
);
    parameter Width = 12;
    parameter Size = 4; // Must be a power of 2
    localparam N = $clog2(Size)-1;
    
    logic[Width-1:0] mem[Size-1:0];
    logic[N:0] rbaddr, rgaddr; // Read addresses (binary, gray)
    logic[N:0] wbaddr, wgaddr; // Write addresses (binary, gray)
    
    // ====================
    // Read handling
    // ====================
    wire[N:0] rbaddrNext = rbaddr+1'b1;
    always @(posedge rclk, negedge rrst_)
        if (!rrst_) begin
            rbaddr <= 0;
            rgaddr <= 0;
        end else if (r & !rempty) begin
            rbaddr <= rbaddrNext;
            rgaddr <= (rbaddrNext>>1)^rbaddrNext;
        end
    
    logic rempty2;
    always @(posedge rclk, posedge aempty)
        // TODO: ensure that before the first clock, empty==true so outside entities don't think they can read
        if (aempty) {rempty, rempty2} <= 2'b11;
        else {rempty, rempty2} <= {rempty2, 1'b0};
    
    assign rd = mem[rbaddr];
    
    // ====================
    // Write handling
    // ====================
    wire[N:0] wbaddrNext = wbaddr+1'b1;
    always @(posedge wclk, negedge wrst_)
        if (!wrst_) begin
            wbaddr <= 0;
            wgaddr <= 0;
        end else if (w & !wfull) begin
            mem[wbaddr] <= wd;
            wbaddr <= wbaddrNext;
            wgaddr <= (wbaddrNext>>1)^wbaddrNext;
        end
    
    logic wfull2;
    always @(posedge wclk, posedge afull, negedge wrst_)
        if (!wrst_) {wfull, wfull2} <= 2'b00;
        else if (afull) {wfull, wfull2} <= 2'b11;
        else {wfull, wfull2} <= {wfull2, 1'b0};
    
    // ====================
    // Async signal generation
    // ====================
    logic dir;
    wire aempty = (rgaddr==wgaddr) & !dir;
    wire afull = (rgaddr==wgaddr) & dir;
    wire dirset = (rgaddr[N]==wgaddr[N-1]) & (rgaddr[N-1]!=wgaddr[N]);
    wire dirclr = (rgaddr[N]!=wgaddr[N-1]) & (rgaddr[N-1]==wgaddr[N]);
    always @(posedge dirset, posedge dirclr, negedge wrst_)
        if (!wrst_) dir <= 0;
        else if (dirset) dir <= 1;
        else dir <= 0;
endmodule




`ifndef SIM

/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        12.000 MHz
 * Requested output frequency:   50.000 MHz
 * Achieved output frequency:    50.250 MHz
 */

module wclkPLL(
    input  clock_in,
    output clock_out,
    output locked
    );

SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),        // DIVR =  0
        .DIVF(7'b1000010),    // DIVF = 66
        .DIVQ(3'b100),        // DIVQ =  4
        .FILTER_RANGE(3'b001)    // FILTER_RANGE = 1
    ) uut (
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .REFERENCECLK(clock_in),
        .PLLOUTCORE(clock_out)
        );

endmodule




/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        12.000 MHz
 * Requested output frequency:   90.000 MHz
 * Achieved output frequency:    90.000 MHz
 */

module rclkPll(
    input  clock_in,
    output clock_out,
    output locked
    );

SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),        // DIVR =  0
        .DIVF(7'b0111011),    // DIVF = 59
        .DIVQ(3'b011),        // DIVQ =  3
        .FILTER_RANGE(3'b001)    // FILTER_RANGE = 1
    ) uut (
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .REFERENCECLK(clock_in),
        .PLLOUTCORE(clock_out)
        );

endmodule

`endif


// module AFIFOTest(input logic clk12mhz);
//     logic rrst_;
//     logic wrst_;
//
//     logic wclk;
//     logic w;
//     logic[11:0] wd;
//     logic wfull;
//     logic rclk;
//     logic r;
//     logic[11:0] rd;
//     logic rempty;
//
//     AFIFO afifo(.*);
//
// `ifdef SIM
//     initial begin
//         $dumpfile("top.vcd");
//         $dumpvars(0, AFIFOTest);
//         #10000000;
//         $finish;
//     end
//
//     // rclk
//     initial begin
//         rclk = 0;
//         #7;
//         forever begin
//             rclk = !rclk;
//             #3;
//         end
//     end
//
//     // wclk
//     initial begin
//         wclk = 0;
//         forever begin
//             wclk = !wclk;
//             #42;
//         end
//     end
// `else
//     wclkPLL pll1(.clock_in(clk12mhz), .clock_out(wclk));
//     rclkPLL pll2(.clock_in(clk12mhz), .clock_out(rclk));
// `endif
//
//     // Produce values
//     always @(posedge wclk, negedge wrst_) begin
//         if (!wrst_) begin
//             w <= 1;
//             wd <= 0;
//         end else if (!wfull) begin
//             // We wrote a value, continue to the next one
//             wd <= wd+1'b1;
//         end
//     end
//
//     // Consume values
//     logic[11:0] rval;
//     logic rvalValid;
//     logic rok;
//     always @(posedge rclk, negedge rrst_) begin
//         if (!rrst_) begin
//             rvalValid <= 0;
//             rok <= 1;
//
//         end else if (rok) begin
//             if (!rempty) begin
//                 rval <= rd;
//                 rvalValid <= 1;
//
//                 $display("Read value: %h", rd);
//
//                 // Check if the current value is the previous value +1
//                 if (rvalValid & (rd!=(rval+1'b1))) begin
//                     rok <= 0;
//                 end
//             end
//         end
//     end
// endmodule



// module AFIFOTest(input logic clk12mhz);
//     logic rrst_;
//     logic wrst_;
//
//     logic wclk;
//     logic w;
//     logic[11:0] wd;
//     logic wfull;
//     logic rclk;
//     logic r;
//     logic[11:0] rd;
//     logic rempty;
//
//     AFIFO afifo(.*);
//
// `ifdef SIM
//     initial begin
//         $dumpfile("top.vcd");
//         $dumpvars(0, AFIFOTest);
//         #10000000;
//         $finish;
//     end
//
//     // rclk
//     initial begin
//         rclk = 0;
//         #7;
//         forever begin
//             rclk = !rclk;
//             #3;
//         end
//     end
//
//     // wclk
//     initial begin
//         wclk = 0;
//         forever begin
//             wclk = !wclk;
//             #42;
//         end
//     end
// `else
//     wclkPLL pll1(.clock_in(clk12mhz), .clock_out(wclk));
//     rclkPLL pll2(.clock_in(clk12mhz), .clock_out(rclk));
// `endif
//
//     // Produce values
//     always @(posedge wclk, negedge wrst_) begin
//         if (!wrst_) begin
//             w <= 1;
//             wd <= 0;
//         end else if (!wfull) begin
//             // We wrote a value, continue to the next one
//             wd <= wd+1'b1;
//         end
//     end
//
//     // Consume values
//     logic[11:0] rval;
//     logic rvalValid;
//     logic rok;
//     always @(posedge rclk, negedge rrst_) begin
//         if (!rrst_) begin
//             rvalValid <= 0;
//             rok <= 1;
//
//         end else if (rok) begin
//             if (!rempty) begin
//                 rval <= rd;
//                 rvalValid <= 1;
//
//                 $display("Read value: %h", rd);
//
//                 // Check if the current value is the previous value +1
//                 if (rvalValid & (rd!=(rval+1'b1))) begin
//                     rok <= 0;
//                 end
//             end
//         end
//     end
// endmodule







`ifdef SIM
//
// module AFIFOTestSim();
//     logic rrst_;
//     logic wrst_;
//
//     logic wclk;
//     logic w;
//     logic[11:0] wd;
//     logic wfull;
//     logic rclk;
//     logic r;
//     logic[11:0] rd;
//     logic rempty;
//
//     logic[11:0] tmp;
//
//
//
//     // task WaitUntilCommandAccepted;
//     //     wait (!clk && cmdReady);
//     //     wait (clk && cmdReady);
//     //
//     //     // Wait one time unit, so that changes that are made after aren't
//     //     // sampled by the SDRAM controller on this clock edge
//     //     #1;
//     // endtask
//
//     task Read(output logic[11:0] val);
//         `assert(!rempty);
//
//         // Get the current value that's available
//         val = rd;
//         $display("Read byte: %h", val);
//         if (!rclk) #1; // Ensure rclk isn't transitioning on this step
//
//         // Read a new value
//         wait(!rclk);
//         #1;
//         r = 1;
//         wait(rclk);
//         #1;
//         r = 0;
//     endtask
//
//     task Write(input logic[11:0] val);
//         `assert(!wfull);
//
//         if (!wclk) #1; // Ensure wclk isn't transitioning on this step
//         wait(!wclk);
//         #1;
//         wd = val;
//         w = 1;
//         wait(wclk);
//         #1;
//         w = 0;
//
//         $display("Wrote byte: %h", val);
//     endtask
//
//     task WaitUntilCanRead;
//         wait(!rempty && !rclk);
//     endtask
//
//     task WaitUntilCanWrite;
//         wait(!wfull && !wclk);
//     endtask
//
//
//
//     AFIFO afifo(.*);
//
//     initial begin
//         $dumpfile("top.vcd");
//         $dumpvars(0, AFIFOTestSim);
//
//         wclk = 0;
//         w = 0;
//         wd = 0;
//         rclk = 0;
//         r = 0;
//
//         #10000000;
//         //        #200000000;
//         //        #2300000000;
//         $finish;
//     end
//
//     // Consumer
//     initial begin
//         // Async reset assert
//         rrst_ = 0;
//         #5;
//         // Sync reset deassert
//         wait(rclk);
//         rrst_ = 1;
//
//         forever begin
//             WaitUntilCanRead;
//             Read(tmp);
//         end
//     end
//
//     // Producer
//     initial begin
//         int i;
//
//         // Async reset assert
//         wrst_ = 0;
//         #10;
//         // Sync reset deassert
//         wait(wclk);
//         wrst_ = 1;
//
//         forever begin
//             // WaitUntilCanWrite;
//             Write(i);
//             i++;
//         end
//     end
//
//     // rclk
//     initial begin
//         #7;
//         rclk = 0;
//         forever begin
//             rclk = !rclk;
//             #3;
//         end
//     end
//
//     // wclk
//     initial begin
//         wclk = 0;
//         forever begin
//             wclk = !wclk;
//             #42;
//         end
//     end
// endmodule
//
`endif

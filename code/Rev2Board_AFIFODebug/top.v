`include "../ClockGen.v"
`include "../AFIFO.v"

`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0 /* synthesis syn_keep=1 */
);
    // ====================
    // Clock PLL (48.75 MHz)
    // ====================
    localparam WriteClkFreq = 48750000;
    wire writeClk;
    ClockGen #(
        .FREQ(WriteClkFreq),
        .DIVR(0),
        .DIVF(64),
        .DIVQ(4),
        .FILTER_RANGE(1)
    ) writeClockGen(.clk12mhz(clk12mhz), .clk(writeClk));
    
    
    // ====================
    // Clock PLL (81 MHz)
    // ====================
    localparam ReadClkFreq = 81000000;
    wire readClk;
    ClockGen #(
        .FREQ(ReadClkFreq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) readClockGen(.clk12mhz(clk12mhz), .clk(readClk));
    
    reg readTrigger = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    wire[15:0] readData;
    wire readDataReady;
    reg[9:0] readDelay = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    
    reg writeTrigger = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    reg[15:0] writeData = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    reg[11:0] writeDelay = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    AFIFO #(.Width(16), .Size(128)) pixq(
        .rclk(readClk),
        .r(readTrigger),
        .rd(readData),
        .rok(readDataReady),
        
        .wclk(writeClk),
        .w(writeTrigger),
        .wd(writeData),
        .wok()
    );
    
    always @(posedge writeClk) begin
        if (!(&writeDelay)) begin
            writeDelay <= writeDelay+1;
            writeTrigger <= 0;
            writeData <= 0;
        
        end else begin
            writeTrigger <= 1;
            writeData <= 16'hFFFF;
        end
    end
    
    reg[15:0] readCounter = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    always @(posedge readClk) begin
        if (!(&readDelay)) begin
            readDelay <= readDelay+1;
            readTrigger <= 0;
            led <= 0;
        
        end else begin
            readTrigger <= 1;
            
            if (readData && readTrigger) begin
                readCounter <= readCounter+1;
                
                if (!led) begin
                    if (readData == 16'h0000) begin
                        $display("GOT DATA 0000");
                        // led <= readCounter;
                        // led[0] <= 1;
                    end else if (readData == 16'hFFFF) begin
                        // $display("GOT DATA FFFF");
                        // led[1] <= 1;
                    end else begin
                        $display("GOT DATA XXXX");
                        
                        if (&readData[3:0])
                            led[0] <= 1;
                        
                        if (&readData[7:4])
                            led[1] <= 1;
                        
                        if (&readData[11:8])
                            led[2] <= 1;
                        
                        if (&readData[15:12])
                            led[3] <= 1;

                        
                        // led <= readCounter;
                    end
                end
            end
        end
    end
    
`ifdef SIM
    // reg sim_clk12mhz = 0;
    // assign clk12mhz = sim_clk12mhz;
    //
    // initial begin
    //     forever begin
    //         #($urandom % 42);
    //         sim_clk12mhz = 0;
    //         #42;
    //         sim_clk12mhz = 1;
    //         #42;
    //     end
    // end
    
    // initial begin
    //     // $dumpfile("top.vcd");
    //     // $dumpvars(0, Top);
    //
    //     // #10000000;
    //     // $finish;
    // end
    
`endif
   
    
// `ifdef SIM
//     reg sim_debug_clk = 0;
//     reg sim_debug_cs = 0;
//     reg[7:0] sim_debug_di_shiftReg = 0;
//
//     assign debug_clk = sim_debug_clk;
//     assign debug_cs = sim_debug_cs;
//     assign debug_di = sim_debug_di_shiftReg[7];
//
//     reg sim_pix_dclk = 0;
//     reg[11:0] sim_pix_d = 0;
//     reg sim_pix_fv = 0;
//     reg sim_pix_lv = 0;
//
//     assign pix_dclk = sim_pix_dclk;
//     assign pix_d = sim_pix_d;
//     assign pix_fv = sim_pix_fv;
//     assign pix_lv = sim_pix_lv;
//
//     task WriteByte(input[7:0] b);
//         sim_debug_di_shiftReg = b;
//         repeat (8) begin
//             wait (sim_debug_clk);
//             wait (!sim_debug_clk);
//             sim_debug_di_shiftReg = sim_debug_di_shiftReg<<1;
//         end
//     endtask
//
//     initial begin
//         sim_pix_d <= 0;
//         sim_pix_fv <= 1;
//         sim_pix_lv <= 1;
//         #1000;
//
//         repeat (3) begin
//             sim_pix_fv <= 1;
//             #100;
//
//             repeat (8) begin
//                 sim_pix_lv <= 1;
//                 sim_pix_d <= 12'hCAF;
//                 #1000;
//                 sim_pix_lv <= 0;
//                 #100;
//             end
//
//             sim_pix_fv <= 0;
//             #1000;
//         end
//
//         $finish;
//     end
//
//
//     initial begin
//         $dumpfile("top.vcd");
//         $dumpvars(0, Top);
//     end
//
//     // Assert chip select
//     initial begin
//         // Wait for ClockGen to start its clock
//         wait(clk);
//         #100;
//         wait (!sim_debug_clk);
//         sim_debug_cs = 1;
//     end
//
//     initial begin
//         // Wait for ClockGen to start its clock
//         wait(clk);
//
//         // Wait arbitrary amount of time
//         #1057;
//         wait(clk);
//
//         WriteByte(MsgType_PixCapture);     // Message type
//         #1000000;
//     end
//
//     initial begin
//         // Wait for ClockGen to start its clock
//         wait(clk);
//         #100;
//
//         forever begin
//             // 50 MHz dclk
//             sim_pix_dclk = 1;
//             #10;
//             sim_pix_dclk = 0;
//             #10;
//         end
//     end
//
//     initial begin
//         // Wait for ClockGen to start its clock
//         wait(clk);
//         #100;
//
//         forever begin
//             sim_debug_clk = 0;
//             #10;
//             sim_debug_clk = 1;
//             #10;
//         end
//     end
// `endif
    
endmodule

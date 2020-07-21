`include "../ClockGen.v"
`include "../AFIFO.v"

`timescale 1ns/1ps




module PixController #(
    parameter ClkFreq = 12000000,       // `clk` frequency
    parameter ExtClkFreq = 12000000     // Image sensor's external clock frequency
)(
    input wire          clk,
    output wire[11:0]   pixel,
    output wire         pixel_ready,
    input wire          pixel_trigger,
    input wire          pix_dclk
);
    reg[11:0] pixelData = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    reg frameValid = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    reg lineValid = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    always @(posedge pix_dclk) begin
        pixelData <= 12'hFFF;
        frameValid <= 1;
        lineValid <= 1;
    end
    
    wire pixq_rclk = clk;
    wire pixq_readOK;
    wire pixq_readTrigger = pixel_trigger;
    wire[15:0] pixq_readData;
    wire pixq_wclk = pix_dclk;
    wire pixq_writeTrigger = frameValid && lineValid;
    wire[15:0] pixq_writeData = pixelData;
    wire pixq_writeOK;
    AFIFO #(.Width(16), .Size(256)) pixq(
        .rclk(pixq_rclk),
        .r(pixq_readTrigger),
        .rd(pixq_readData),
        .rok(pixq_readOK),
        .wclk(pixq_wclk),
        .w(pixq_writeTrigger),
        .wd(pixq_writeData),
        .wok(pixq_writeOK)
    );
    
    assign pixel[11:0] = pixq_readData[11:0];
    assign pixel_ready = pixq_readOK;
endmodule



module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0 /* synthesis syn_keep=1 */
);
    // ====================
    // Clock PLL (81 MHz)
    // ====================
    localparam ClkFreq = 81000000;
    wire clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    
    
    
    
    
    
    
    // ====================
    // Pix Controller
    // ====================
    wire[11:0] pix_pixel;
    wire pix_pixelReady;
    reg pix_pixelTrigger = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    PixController #(
        .ExtClkFreq(12000000),
        .ClkFreq(ClkFreq)
    ) pixController(
        .clk(clk),
        
        .pixel(pix_pixel),
        .pixel_ready(pix_pixelReady),
        .pixel_trigger(pix_pixelTrigger),
        .pix_dclk(clk12mhz)
        
        // .led(led)
    );
    
    reg[11:0] delay = 0 /* synthesis syn_preserve=1 syn_keep=1 */;
    always @(posedge clk) begin
        if (!(&delay)) begin
            delay <= delay+1;
            led <= 0;
        
        end else begin
            pix_pixelTrigger <= 1;
            // Handle reading a new pixel into `ram_cmdWriteData`, or an overflow register
            if (pix_pixelReady && pix_pixelTrigger) begin
                
                if (pix_pixel == 12'h000) begin
                    led <= led+1'b1;
                end
                
                // if (pix_pixel == 12'h000) begin
                //     $display("GOT 000");
                //     led[0] <= 1;
                //
                // end else if (pix_pixel == 12'hFFF) begin
                //     // $display("GOT 111");
                //     led[1] <= 1;
                //
                // end else begin
                //     $display("GOT ???");
                //     led[2] <= 1;
                // end
            end
        end
    end
    
`ifdef SIM
    reg sim_clk12mhz = 0;
    assign clk12mhz = sim_clk12mhz;
    
    initial begin
        forever begin
            #($urandom % 42);
            sim_clk12mhz = 0;
            #42;
            sim_clk12mhz = 1;
            #42;
        end
    end
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end    
    
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

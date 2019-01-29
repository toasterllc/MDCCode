// `define SYNTH
`timescale 1ns/1ps
`include "SDRAMController.v"
`include "4062mt48lc8m16a2/mt48lc8m16a2.v"

// module IcestickSDRAMTest(
// `ifdef SYNTH
//     input logic clk,
//     input logic rst,
// `else
//     output logic clk,
//     output logic rst,
// `endif
//
//     output logic ledRed,
//     output logic ledGreen,
//
//     output logic sdram_clk,
//     output logic sdram_cke,
//     output logic[7:0] sdram_a,
//     output logic sdram_ras_,
//     output logic sdram_cas_,
//     output logic sdram_we_,
//     output logic sdram_dqm,
//     inout logic[7:0] sdram_dq
// );
//
//     logic           internal_sdram_clk;
//     logic           internal_sdram_cke;
//     logic[1:0]      internal_sdram_ba;
//     logic[11:0]     internal_sdram_a;
//     logic           internal_sdram_cs_;
//     logic           internal_sdram_ras_;
//     logic           internal_sdram_cas_;
//     logic           internal_sdram_we_;
//     logic           internal_sdram_ldqm;
//     logic           internal_sdram_udqm;
//     logic[15:0]     internal_sdram_dq;
//
//     assign sdram_clk    = internal_sdram_clk;
//     assign sdram_cke    = internal_sdram_cke;
//     assign sdram_a      = internal_sdram_a[7:0];
//     assign sdram_ras_   = internal_sdram_ras_;
//     assign sdram_cas_   = internal_sdram_cas_;
//     assign sdram_we_    = internal_sdram_we_;
//     assign sdram_dqm    = internal_sdram_ldqm;
//     assign sdram_dq     = internal_sdram_dq[7:0];
//
//     localparam StatusOK = 1;
//     localparam StatusFailed = 0;
//
//     `define dataFromAddress(addr) ~addr
//
//     logic cmdReady;
//     logic cmdTrigger;
//     logic[22:0] cmdAddr;
//     logic cmdWrite;
//     logic[15:0] cmdWriteData;
//     logic[15:0] cmdReadData;
//     logic cmdReadDataValid;
//
//     logic status;
//     logic[7:0] readAddr;
//
//     assign cmdTrigger = (cmdReady && status==StatusOK);
//     assign cmdWriteData = `dataFromAddress(cmdAddr);
//
//     assign ledRed = (status==StatusFailed);
//     assign ledGreen = (status==StatusOK);
//
//     always @(posedge clk) begin
//         if (rst) begin
//             cmdWrite <= 1;
//             cmdAddr <= 0;
//
//             status <= StatusOK;
//             readAddr <= 0;
//
//         end else if (status == StatusOK) begin
//             if (cmdReadDataValid) begin
//                 // Verify that the data read out is what we expect
//                 if (cmdReadData == `dataFromAddress(readAddr))
//                     status <= StatusOK;
//                 else begin
//                     status <= StatusFailed;
//                 end
//
//                 readAddr <= readAddr+1;
//             end
//
//             // Update our state
//             if (cmdReady) begin
//                 if (cmdAddr < 8'hFF) begin
//                     cmdAddr <= cmdAddr+1;
//                 end else begin
//                     cmdWrite <= !cmdWrite;
//                     cmdAddr <= 0;
//                 end
//             end
//         end
//     end
//
//     SDRAMController sdramController(
//         .clk(clk),
//         .rst(rst),
//
//         .cmdReady(cmdReady),
//         .cmdTrigger(cmdTrigger),
//         .cmdAddr(cmdAddr),
//         .cmdWrite(cmdWrite),
//         .cmdWriteData(cmdWriteData),
//         .cmdReadData(cmdReadData),
//         .cmdReadDataValid(cmdReadDataValid),
//
//         .sdram_clk(internal_sdram_clk),
//         .sdram_cke(internal_sdram_cke),
//         .sdram_ba(internal_sdram_ba),
//         .sdram_a(internal_sdram_a),
//         .sdram_cs_(internal_sdram_cs_),
//         .sdram_ras_(internal_sdram_ras_),
//         .sdram_cas_(internal_sdram_cas_),
//         .sdram_we_(internal_sdram_we_),
//         .sdram_ldqm(internal_sdram_ldqm),
//         .sdram_udqm(internal_sdram_udqm),
//         .sdram_dq(internal_sdram_dq)
//     );
//
//     // `ifndef SYNTH
//     //     mt48lc8m16a2 ram(
//     //         .Clk(internal_sdram_clk),
//     //         .Dq(internal_sdram_dq),
//     //         .Addr(internal_sdram_a),
//     //         .Ba(internal_sdram_ba),
//     //         .Cke(internal_sdram_cke),
//     //         .Cs_n(internal_sdram_cs_),
//     //         .Ras_n(internal_sdram_ras_),
//     //         .Cas_n(internal_sdram_cas_),
//     //         .We_n(sdram_we_),
//     //         .Dqm({sdram_udqm, sdram_ldqm})
//     //     );
//     // `endif
//
//     initial begin
//         $dumpfile("IcestickSDRAMTest.vcd");
//         $dumpvars(0, IcestickSDRAMTest);
//
//         // Reset
//         rst = 1;
//         #100;
//         rst = 0;
//
//         #1000000;
//         $finish;
//     end
//
//     initial begin
//         clk = 0;
//         forever begin
//             clk = !clk;
//             #5;
//         end
//     end
// endmodule



module TestController(
    input logic         clk,
    input logic         rst,
    
    output logic        ledRed,
    output logic        ledGreen,
    
    output logic        sdram_clk,
    output logic        sdram_cke,
    // Use the high bits of `sdram_a` because we need A[10] for precharging to work!
    output logic[11:0]  sdram_a,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_dqm,
    inout logic[15:0]   sdram_dq
);
    
    logic               cmdReady;
    logic               cmdTrigger;
    logic[22:0]         cmdAddr;
    logic               cmdWrite;
    logic[15:0]         cmdWriteData;
    logic[15:0]         cmdReadData;
    logic               cmdReadDataValid;
    
    logic[1:0]          sdram_ba;
    
    localparam StatusOK = 1;
    localparam StatusFailed = 0;
    
    `define dataFromAddress(addr) ~addr
    
    logic status;
    logic[15:0] readAddr;
    
    assign cmdTrigger = (cmdReady && status==StatusOK);
    assign cmdWriteData = `dataFromAddress(cmdAddr);
    
    assign ledRed = (status==StatusFailed);
    assign ledGreen = (status==StatusOK);
    
    SDRAMController sdramController(
        .clk(clk),
        .rst(rst),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_ldqm(sdram_dqm),
        .sdram_udqm(),
        .sdram_dq(sdram_dq)
    );
    
    always @(posedge clk) begin
        if (rst) begin
            cmdWrite <= 1;
            cmdAddr <= 0;
            
            status <= StatusOK;
            readAddr <= 0;
        
        end else if (status == StatusOK) begin
            if (cmdReadDataValid) begin
                // Verify that the data read out is what we expect
                if (cmdReadData == `dataFromAddress(readAddr))
                    status <= StatusOK;
                else
                    status <= StatusFailed;
                
                readAddr <= readAddr+1;
            end
            
            // Update our state
            if (cmdReady) begin
                if (cmdAddr < 8'hFF) begin
                    cmdAddr <= cmdAddr+1;
                end else begin
                    cmdWrite <= !cmdWrite;
                    cmdAddr <= 0;
                end
            end
        end
    end
endmodule

module TopSim(
    output logic        ledRed,
    output logic        ledGreen,
    
    output logic        sdram_clk,
    output logic        sdram_cke,
    // Use the high bits of `sdram_a` because we need A[10] for precharging to work!
    output logic[11:0]  sdram_a,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_dqm,
    inout logic[15:0]   sdram_dq
);
    
    logic clk;
    logic rst;
    
    TestController testController(
        .clk(clk),
        .rst(rst),
        .ledRed(ledRed),
        .ledGreen(ledGreen),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_a(sdram_a),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_dqm(sdram_dqm),
        .sdram_dq(sdram_dq)
    );
    
    mt48lc8m16a2 sdram(
        .Clk(sdram_clk),
        .Dq(sdram_dq),
        .Addr(sdram_a),
        .Ba(2'b0),
        .Cke(sdram_cke),
        .Cs_n(1'b0),
        .Ras_n(sdram_ras_),
        .Cas_n(sdram_cas_),
        .We_n(sdram_we_),
        .Dqm({sdram_dqm, sdram_dqm})
    );
    
    initial begin
        $dumpfile("IcestickSDRAMTest.vcd");
        $dumpvars(0, TopSim);
        
        // Reset
        rst = 1;
        #100;
        rst = 0;
        
        #1000000;
        $finish;
    end
    
    initial begin
        clk = 0;
        forever begin
            clk = !clk;
            #5;
        end
    end
endmodule

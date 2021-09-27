`ifndef FletcherChecksum_v
`define FletcherChecksum_v

`include "Util.v"

module OnesComplementAdder #(
    parameter Width         = 32
)(
    input wire[Width-1:0]   a,
    input wire[Width-1:0]   b,
    output wire[Width-1:0]  y
);
    wire[Width:0] sum = a+b;
    wire carry = sum[Width];
    // assign y = sum;
    assign y = sum+carry;
endmodule

// module FletcherChecksum #(
//     parameter Width         = 32,
//     localparam WidthHalf    = Width/2
// )(
//     input wire                  clk,
//     input wire                  rst,
//     input wire                  en,
//     input wire[WidthHalf-1:0]   din,
//     output wire[Width-1:0]      dout
// );
//     reg[WidthHalf+2:0]  asum = 0;
//     reg[WidthHalf+2:0]  asumtmp = 0;
//     reg[WidthHalf+2:0]  bsum = 0;
//
//     wire[WidthHalf:0] aadd = (`LeftBit(asum,0) ? {1'b0, {WidthHalf{'1}}} : {1'b1, {WidthHalf-1{'0}}, 1'b1});
//     wire[WidthHalf:0] badd = (`LeftBit(bsum,0) ? {1'b0, {WidthHalf{'1}}} : {1'b1, {WidthHalf-1{'0}}, 1'b1});
//
//     wire[WidthHalf-1:0] a = asum[WidthHalf-1:0]-1;
//     wire[WidthHalf-1:0] b = bsum[WidthHalf-1:0]-1;
//
//     reg enprev = 0;
//
//     always @(posedge clk) begin
//         if (rst) begin
//             asum <= 0;
//             asumtmp <= 0;
//             bsum <= 0;
//             enprev <= 0;
//             $display("[FletcherChecksum]\t\t RESET");
//
//         end else begin
//             enprev <= en;
//
//             if (en) begin
//                 asum <= ((asum+aadd)+din);
//                 asumtmp <= (asum+din);
//             end else begin
//                 asum <= asum+aadd;
//             end
//
//             if (enprev) begin
//                 bsum <= ((bsum+badd)+asumtmp);
//             end else begin
//                 bsum <= bsum+badd;
//             end
//
//             $display("[FletcherChecksum]\t\t bsum:%h badd:%h \t asum:%h aadd:%h \t din:%h \t\t rst:%h en:%h [checksum: %h]", bsum, badd, asum, aadd, din, rst, en, dout);
//         end
//     end
//     // assign dout = {bsum[WidthHalf-1:0], asum[WidthHalf-1:0]};
//     assign dout = {b, a};
// endmodule

module FletcherChecksum #(
    parameter Width         = 32,
    localparam WidthHalf    = Width/2
)(
    input wire                  clk,
    input wire                  rst,
    input wire                  en,
    input wire[WidthHalf-1:0]   din,
    output wire[Width-1:0]      dout
);
    reg[WidthHalf+2:0]  asum = 0;
    reg[WidthHalf+2:0]  asumtmp = 0;
    reg[WidthHalf+2:0]  bsum = 0;
    
    wire[WidthHalf-1:0] asub = (!`LeftBit(asum,0) ? {WidthHalf{'1}} : 0);
    wire[WidthHalf-1:0] bsub = (!`LeftBit(bsum,0) ? {WidthHalf{'1}} : 0);
    
    wire[WidthHalf-1:0] a = asum[WidthHalf-1:0]-1;
    wire[WidthHalf-1:0] b = bsum[WidthHalf-1:0]-1;
    
    reg enprev = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            asum <= 0;
            asumtmp <= 0;
            bsum <= 0;
            enprev <= 0;
            $display("[FletcherChecksum]\t\t RESET");
        
        end else begin
            enprev <= en;
            
            if (en) begin
                asum <= ((asum-asub)+din);
                asumtmp <= (asum+din);
            end else begin
                asum <= asum-asub;
            end
            
            if (enprev) begin
                bsum <= ((bsum-bsub)+asumtmp);
            end else begin
                bsum <= bsum-bsub;
            end
            
            $display("[FletcherChecksum]\t\t bsum:%h bsub:%h \t asum:%h asub:%h \t din:%h \t\t rst:%h en:%h [checksum: %h]", bsum, bsub, asum, asub, din, rst, en, dout);
        end
    end
    // assign dout = {bsum[WidthHalf-1:0], asum[WidthHalf-1:0]};
    assign dout = {b, a};
endmodule

module FletcherChecksumCorrect #(
    parameter Width         = 32,
    localparam WidthHalf    = Width/2
)(
    input wire                  clk,
    input wire                  rst,
    input wire                  en,
    input wire[WidthHalf-1:0]   din,
    output wire[Width-1:0]      dout
);
    reg[WidthHalf-1:0] a = 0;
    reg[WidthHalf-1:0] b = 0;
    reg enprev = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
            enprev <= 0;
        
        end else begin
            enprev <= en;
            if (en)     a <= ({1'b0,a}+din) % {WidthHalf{'1}};
            if (enprev) b <= ({1'b0,b}+a  ) % {WidthHalf{'1}};
            // $display("[FletcherChecksumCorrect]\t b:%h \t\t a:%h \t\t din:%h \t\t en:%h", b, a, din, en);
        end
    end
    assign dout = {b, a};
endmodule

`endif

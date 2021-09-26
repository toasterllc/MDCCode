`ifndef FletcherChecksum_v
`define FletcherChecksum_v

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
    reg[Width:0]  asum = 0;
    reg[Width:0]  bsum = 0;
    reg[Width:0]  aadd = 0;
    reg[Width:0]  badd = 0;
    reg[Width:0]  asub = 0;
    reg[Width:0]  bsub = 0;
    reg[Width:0]  asumdelayed = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            asum <= 0;
            bsum <= 0;
            aadd <= 0;
            badd <= 0;
            asub <= 0;
            bsub <= 0;
            asumdelayed <= 0;
        
        end begin
            if (en) begin
                asum <= ((asum+aadd-asub)+din);
                bsum <= ((bsum+badd-bsub)+asum);
            end else begin
                asum <= (asum+aadd-asub);
                bsum <= (bsum+badd-bsub);
            end
            
            $display("asum:%0d asub:%0d bsum:%0d bsub:%0d din:%0d", asum, asub, bsum, bsub, din);
            
            aadd <= 0;
            asub <= 0;
            if (aadd===0 && asub===0) begin
                if (asum[Width]) begin
                    // Add 255
                    aadd <= {WidthHalf{'1}};
                end else if ((|asum[Width-1:WidthHalf] || &asum[WidthHalf-1:0])) begin
                    // Subtract 255
                    $display("asub: NEED TO SUB 255");
                    asub <= {WidthHalf{'1}};
                end
            end
            
            badd <= 0;
            bsub <= 0;
            if (badd===0 && bsub===0) begin
                if (bsum[Width]) begin
                    // Add 255
                    badd <= {WidthHalf{'1}};
                end else if ((|bsum[Width-1:WidthHalf] || &bsum[WidthHalf-1:0])) begin
                    // Subtract 255
                    $display("bsub: NEED TO SUB 255");
                    bsub <= {WidthHalf{'1}};
                end
            end
            
            asumdelayed <= asum;
        end
    end
    assign dout[Width-1:WidthHalf]  = bsum;// % {WidthHalf{'1}};
    assign dout[WidthHalf-1:0]      = asum;// % {WidthHalf{'1}};
endmodule

`endif

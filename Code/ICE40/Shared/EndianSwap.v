`ifndef EndianSwap_v
`define EndianSwap_v

`include "Util.v"

module EndianSwap #(
    parameter Width = 32
)();
    function[Width-1:0] Swap;
        input[Width-1:0] din;
        begin
            for (int i=0; i<Width/2; i=i+8) begin
                `RightBits(Swap,i,8) = `LeftBits(din,i,8);
                `LeftBits(Swap,i,8)  = `RightBits(din,i,8);
            end
        end
    endfunction
endmodule

`endif

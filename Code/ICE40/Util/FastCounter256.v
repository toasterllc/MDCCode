`ifndef FastCounter256_v
`define FastCounter256_v

module FastCounter256(
    input wire clk,
    output reg out = 0
);
    reg[255:0] shiftReg = 0;
    reg init = 0;
    always @(posedge clk) begin
        out <= 0;
        if (!init || shiftReg[255]) begin
            init <= 1;
            shiftReg <= 256'b1;
            out <= 1;
        end else begin
            shiftReg <= shiftReg<<1;
        end
    end
    
    
    // reg[7:0] shiftReg = 0;
    // reg[1:0] counter = 0;
    // always @(posedge clk, negedge rst_) begin
    //     out <= 0;
    //     if (!rst_) begin
    //         shiftReg <= {7'b0, 1'b1};
    //         counter <= 5'b11111;
    //
    //     end else begin
    //         if (shiftReg[7]) begin
    //             shiftReg <= 8'b1;
    //             counter <= counter-1;
    //             if (!counter) out <= 1;
    //
    //         end else begin
    //             shiftReg <= shiftReg<<1;
    //         end
    //     end
    // end
endmodule

`endif

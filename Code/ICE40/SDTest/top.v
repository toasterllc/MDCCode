`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output wire[3:0] led,
    output wire sd_init,
    output wire sd_clk,
    output wire sd_cmd,
);
    reg[20:0] counter = 0;
    always @(posedge clk24mhz) begin
        counter <= counter+1;
    end
    assign led[3:0] = {4{counter[$size(counter)-1]}};
    assign sd_clk = counter[$size(counter)-1];
    assign sd_cmd = counter[$size(counter)-1];
    assign sd_init = 1'b1;
endmodule

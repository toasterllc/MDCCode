`timescale 1ns/1ps

module Top(
    input wire ice_img_clk16mhz,
    output wire[3:0] ice_led
);
    wire clk = ice_img_clk16mhz;
    
    reg[20:0] counter = 0;
    always @(posedge clk) begin
        counter <= counter+1;
    end
    
    assign ice_led[3:0] = {4{counter[$size(counter)-1]}};
endmodule

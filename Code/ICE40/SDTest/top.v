`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output wire[3:0] led,
    output wire sd_init,
    output wire sd_clk,
    output wire sd_cmd,
    output wire[3:0] sd_dat,
);
    reg[5:0] counter = 0;
    always @(posedge clk24mhz) begin
        counter <= counter+1;
    end
    assign led[3:0] = {4{counter[$size(counter)-1]}};
    assign sd_clk = counter[$size(counter)-1];
    assign sd_cmd = counter[$size(counter)-1];
    assign sd_dat[3:0] = {4{counter[$size(counter)-1]}};
    assign sd_init = 1'b1;
endmodule

// Test states


// ICE_SD_INIT = 0
//
//  ICE_SD_INIT     constant 0          √
//  ICE_SD_CLK      oscillating 1.8V    √
//  ICE_SD_CMD      oscillating 1.8V    √
//  ICE_SD_DAT0     oscillating 1.8V    √
//  ICE_SD_DAT1     oscillating 1.8V    √
//  ICE_SD_DAT2     oscillating 1.8V    √
//  ICE_SD_DAT3     oscillating 1.8V    √
//  
//  SD_CLK          oscillating 1.8V    √
//  SD_CMD          oscillating 1.8V    √
//  SD_DAT0         oscillating 1.8V    √
//  SD_DAT1         oscillating 1.8V    √
//  SD_DAT2         oscillating 1.8V    √
//  SD_DAT3         oscillating 1.8V    √



// ICE_SD_INIT = 1
//
//  ICE_SD_INIT     constant 1          √
//  ICE_SD_CLK      oscillating 1.8V    √
//  ICE_SD_CMD      oscillating 1.8V    √
//  ICE_SD_DAT0     oscillating 1.8V    √
//  ICE_SD_DAT1     oscillating 1.8V    √
//  ICE_SD_DAT2     oscillating 1.8V    √
//  ICE_SD_DAT3     oscillating 1.8V    √
//  
//  SD_CLK          oscillating 2.8V    √
//  SD_CMD          oscillating 2.8V    √
//  SD_DAT0         constant 2.8V       √
//  SD_DAT1         constant 2.8V       √
//  SD_DAT2         constant 2.8V       √
//  SD_DAT3         constant 2.8V       √

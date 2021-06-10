`include "ClockGen.v"
`include "Util.v"

`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output reg[3:0] led = 0,
    output reg sd_clk = 0,
    inout wire sd_cmd,
    inout wire[3:0] sd_dat,
);
    // ====================
    // Clock (375 kHz)
    // ====================
    reg[5:0] clkCounter = 0;
    always @(posedge clk24mhz) begin
        clkCounter <= clkCounter+1;
    end
    wire clk = `LeftBit(clkCounter, 0);
    
    // ====================
    // Slow Clock (1.4 Hz)
    // ====================
    reg[18:0] slowClkCounter = 0;
    always @(posedge clk) begin
        slowClkCounter <= slowClkCounter+1;
    end
    wire slowClk = `LeftBit(slowClkCounter, 0);
    
    // ====================
    // Pin: sd_cmd
    // ====================
    reg sd_cmdOut = 0;
    reg sd_cmdOutEn = 0;
    wire sd_cmdIn;
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_sd_cmd (
        .INPUT_CLK(clk),
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_ENABLE(sd_cmdOutEn),
        .D_OUT_0(sd_cmdOut),
        .D_IN_0(sd_cmdIn)
    );

    // ====================
    // Pin: sd_dat[3:0]
    // ====================
    reg[3:0] sd_datOut = 0;
    reg[3:0] sd_datOutEn = 0;
    wire[3:0] sd_datIn;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_00)
        ) SB_IO_sd_dat (
            .INPUT_CLK(clk),
            .OUTPUT_CLK(clk),
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_ENABLE(sd_datOutEn[i]),
            .D_OUT_0(sd_datOut[i]),
            .D_IN_0(sd_datIn[i])
        );
    end
    
    reg prevSlowClk = 0;
    wire slowClkPulse = slowClk && !prevSlowClk;
    
    // ====================
    // State Machine
    // ====================
    reg[1:0] state = 0;
    always @(posedge clk) begin
        prevSlowClk <= slowClk;
        
        case (state)
        0: begin
            sd_clk <= 0;
            
            sd_cmdOut <= 0;
            sd_cmdOutEn <= 1;
            
            sd_datOut <= 0;
            sd_datOutEn <= 1;
        end
        
        1: begin
            led <= 4'h8;
            state <= state+1;
        end
        
        2: begin
            if (slowClkPulse) begin
                led <= led-1;
                if (led === 4'h1) begin
                    state <= state+1;
                end
            end
        end
        
        3: begin
            // led <= ~led;
        end
        endcase
    end
    
    // // ====================
    // // Slow Clock (375 kHz)
    // // ====================
    // reg[23:0] wideCounter = 0;
    // always @(posedge clk24mhz) begin
    //     led <= `LeftBits(wideCounter, 0, 4);
    //     wideCounter <= wideCounter+1;
    // end
    
    // // ====================
    // // Nets
    // // ====================
    // assign led[3:0] = {4{fastClk}};
    // assign sd_clk = fastClk;
    // assign sd_cmd = fastClk;
    // assign sd_dat[3:0] = {4{fastClk}};
endmodule

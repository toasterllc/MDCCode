`include "ClockGen.v"
`include "Util.v"

`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    
    output reg[2:0] led = 0,
    
    output reg sd_pwr_en = 0,
    output reg sd_clk = 0,
    inout wire sd_cmd,
    inout wire[3:0] sd_dat,
);
    // ====================
    // Clock (375 kHz)
    // ====================
    localparam DelayS = 375000;
    localparam DelayMs = 375;
    localparam Delay10Us = 4;
    reg[5:0] clkCounter = 0;
    always @(posedge clk24mhz) begin
        clkCounter <= clkCounter+1;
    end
    wire clk = `LeftBit(clkCounter, 0);
    
    // ====================
    // Slow Clock (1.4 Hz)
    // ====================
    reg[17:0] slowClkCounter = 0;
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
    
    // ====================
    // sd_pwr_en
    // ====================
    reg sd_pwr_en = 0;
    
    // ====================
    // slowClkPulse
    // ====================
    reg prevSlowClk = 0;
    wire slowClkPulse = slowClk && !prevSlowClk;
    
    // ====================
    // State Machine
    // ====================
    reg[19:0] delay = 0;
    reg[7:0] state = 0;
    always @(posedge clk) begin
        prevSlowClk <= slowClk;
        
        if (delay) delay <= delay-1;
        else begin
            case (state)
            0: begin
                sd_pwr_en <= 0;
                
                sd_clk <= 0;
                
                sd_cmdOut <= 0;
                sd_cmdOutEn <= 1;
                
                sd_datOut <= 4'b0000;
                sd_datOutEn <= 4'b1011; // Don't drive DAT2 -- it's pulled down by a resistor
                
                // Turn on LEDs
                led <= 3'b111;
                
                // Delay 1 second
                delay <= DelayS;
                state <= state+1;
            end
            
            1: begin
                // Turn on SD power
                sd_pwr_en <= 1;
                // Turn off LEDs
                led <= 3'b000;
                // Delay 50 ms
                delay <= 50*DelayMs;
                state <= state+1;
            end
            
            // Start LVS identification
            2: begin
                // Start clock pulse
                sd_clk <= 1;
                delay <= 3*Delay10Us;
                state <= state+1;
            end

            3: begin
                // End clock pulse
                sd_clk <= 0;
                state <= state+1;
            end
            
            4: begin
                if (sd_datIn[2]) led[0] <= 1;
            end
            endcase
        end
    end
endmodule

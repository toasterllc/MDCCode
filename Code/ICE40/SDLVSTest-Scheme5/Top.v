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
    
    reg prevSlowClk = 0;
    wire slowClkPulse = slowClk && !prevSlowClk;
    
    reg[2:0] pulseCounter = 0;
    
    // ====================
    // State Machine
    // ====================
    reg[7:0] state = 0;
    always @(posedge clk) begin
        prevSlowClk <= slowClk;
        pulseCounter <= pulseCounter-1;
        
        case (state)
        0: begin
            sd_clk <= 0;
            
            sd_cmdOut <= 0;
            sd_cmdOutEn <= 1;
            
            sd_datOut <= 4'b0000;
            sd_datOutEn <= 4'b1111;
            
            state <= state+1;
        end
        
        1: begin
            led <= 4'b0111;
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
            led <= 4'b1111;
            if (slowClkPulse) begin
                state <= state+1;
            end
        end
        
        // Start LVS identification
        4: begin
            led <= 0;
            // Start clock pulse
            sd_clk <= 1;
            pulseCounter <= ~0;
            state <= state+1;
        end
        
        5: begin
            // Wait until pulse is complete
            if (!pulseCounter) begin
                state <= state+1;
            end
        end
        
        6: begin
            // End clock pulse
            sd_clk <= 0;
            // Stop driving DAT2, since the SD card is about to start driving it high
            sd_datOutEn[2] <= 0;
            state <= state+1;
        end
        
        7: begin
            if (slowClkPulse) begin
                led[3] <= ~led[3];
                led[2] <= ~led[2];
                led[1] <= ~led[1];
            end
            led[0] <= sd_datIn[2];
        end
        endcase
    end
endmodule

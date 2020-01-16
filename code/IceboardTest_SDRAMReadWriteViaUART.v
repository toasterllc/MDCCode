`define SYNTH
`timescale 1ns/1ps
`include "uart.v"
`include "SDRAMController.v"

module IceboardTest_SDRAMReadWriteViaUART(
    input logic         clk12mhz,

    output logic        ledRed,

    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_udqm,
    output logic        sdram_ldqm,
    inout logic[15:0]   sdram_dq,

    input logic         RS232_Rx_TTL,
    output logic        RS232_Tx_TTL
);
    `define RESET_BIT 26
    
    logic[`RESET_BIT:0] clkDivider;
    always @(posedge clk12mhz) clkDivider <= clkDivider+1;
    
    `ifndef SYNTH
    initial clkDivider = 0;
    `endif
    
    logic clk;
    
//    localparam ClockFrequency = 12000000;       // 12 MHz
//    assign clk = clk12mhz;
//    
//    localparam ClockFrequency =  6000000;     // 6 MHz
//    assign clk = clkDivider[0];
//
//    localparam ClockFrequency =  3000000;     // 3 MHz
//    assign clk = clkDivider[1];
//
    localparam ClockFrequency =  1500000;     // 1.5 MHz
    assign clk = clkDivider[2];
//
//    localparam ClockFrequency =   750000;     // .75 MHz
//    assign clk = clkDivider[3];
    
    // Generate our own reset signal
    // This relies on the fact that the ice40 FPGA resets flipflops to 0 at power up
    logic[12:0] rstCounter;
    logic rst;
    logic lastBit;
    assign rst = !rstCounter[$size(rstCounter)-1];
    always @(posedge clk) begin
        if (rst) begin
            rstCounter <= rstCounter+1;
        end
    end
    
    `ifndef SYNTH
    initial rstCounter = 0;
    `endif
    
    logic               cmdReady;
    logic               cmdTrigger;
    logic               cmdWrite;
    logic[22:0]         cmdAddr;
    logic[15:0]         cmdWriteData;
    logic[15:0]         cmdReadData;
    logic               cmdReadDataValid;
    logic               didRefresh;
    assign ledRed = didRefresh;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        .rst(rst),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        .didRefresh(didRefresh),
        
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_udqm(sdram_udqm),
        .sdram_ldqm(sdram_ldqm),
        .sdram_dq(sdram_dq)
    );
    
    // UART stuff
    reg uartTransmit;
    reg [7:0] uartTxByte;
    wire uartReceived;
    wire [7:0] uartRxByte;
    wire is_receiving;
    wire is_transmitting;
    wire recv_error;
    
    uart #(
        .baud_rate(9600),                 // The baud rate in kilobits/s
        .sys_clk_freq(ClockFrequency)       // The master clock frequency
    )
    uart0(
        .clk(clk),                      // The master clock for this module
        .rst(rst),                      // Synchronous reset
        .rx(RS232_Rx_TTL),                // Incoming serial line
        .tx(RS232_Tx_TTL),                // Outgoing serial line
        .transmit(uartTransmit),              // Signal to transmit
        .tx_byte(uartTxByte),                // Byte to transmit
        .received(uartReceived),              // Indicated that a byte has been received
        .rx_byte(uartRxByte),                // Byte received
        .is_receiving(is_receiving),      // Low when receive line is idle
        .is_transmitting(is_transmitting),// Low when transmit line is idle
        .recv_error(recv_error)           // Indicates error in receiving packet.
    );
    
    logic[3:0]  uartCmdStage;
    logic       uartCmdWrite;
    logic[7:0]  uartCmdAddr;
    logic[7:0]  uartCmdWriteData;
    logic[7:0]  uartCmdReadData;
    logic       uartCmdReadDataValid;
    
    function [7:0] HexASCIIFromNibble;
        input [3:0] n;
        HexASCIIFromNibble = (n<10 ? 8'd48+n : 8'd97-8'd10+n);
    endfunction
    
    function [3:0] NibbleFromHexASCII;
        input [7:0] n;
        NibbleFromHexASCII = (n>=97 ? n-97+10 : n-48);
    endfunction
    
    always @(posedge clk) begin
        if (rst) begin
            cmdTrigger <= 0;
            uartCmdStage <= 0;
            uartTransmit <= 0;
        
        end else begin
            // By default we're not transmitting
            uartTransmit <= 0;
            
            // Disable cmdTrigger once the RAM controller accepts the command
            if (cmdTrigger && cmdReady) begin
                cmdTrigger <= 0;
            end
            
            if (cmdReadDataValid) begin
                // uartCmdReadData <= cmdAddr;
                uartCmdReadData <= cmdReadData[7:0];
                uartCmdReadDataValid <= 1;
            end
            
            // Wait until active transmissions complete
            if (!is_transmitting && !uartTransmit) begin
                case (uartCmdStage)
                
                // ## Get command
                0: begin
                    if (uartReceived) begin
                        // Get command (read or write)
                        uartCmdWrite <= (uartRxByte=="w");
                        // Echo the command
                        uartTxByte <= (uartRxByte=="w" ? "w" : "r");
                        uartTransmit <= 1;
                        // Next stage
                        uartCmdStage <= uartCmdStage+1;
                    end
                end
                
                // ## Get address
                1: begin
                    if (uartReceived) begin
                        // Get address high nibble
                        uartCmdAddr <= NibbleFromHexASCII(uartRxByte)<<4;
                        // Echo typed character
                        uartTxByte <= uartRxByte;
                        uartTransmit <= 1;
                        // Next stage
                        uartCmdStage <= uartCmdStage+1;
                    end
                end
                2: begin
                    if (uartReceived) begin
                        // Get address low nibble
                        uartCmdAddr <= uartCmdAddr|NibbleFromHexASCII(uartRxByte);
                        // Echo typed character
                        uartTxByte <= uartRxByte;
                        uartTransmit <= 1;
                        // Next stage
                        if (uartCmdWrite) uartCmdStage <= uartCmdStage+1;
                        // If we're reading, skip reading the byte to write
                        else uartCmdStage <= uartCmdStage+3;
                    end
                end
                
                // ## Get byte to write
                3: begin
                    if (uartReceived) begin
                        // Get address high nibble
                        uartCmdWriteData <= NibbleFromHexASCII(uartRxByte)<<4;
                        // Echo typed character
                        uartTxByte <= uartRxByte;
                        uartTransmit <= 1;
                        // Next stage
                        uartCmdStage <= uartCmdStage+1;
                    end
                end
                4: begin
                    if (uartReceived) begin
                        // Get address low nibble
                        uartCmdWriteData <= uartCmdWriteData|NibbleFromHexASCII(uartRxByte);
                        // Echo typed character
                        uartTxByte <= uartRxByte;
                        uartTransmit <= 1;
                        // Next stage
                        uartCmdStage <= uartCmdStage+1;
                    end
                end
                
                // ## Issue command to RAM
                5: begin
                    // Issue the command to the SDRAM
                    cmdAddr <= {15'h0, uartCmdAddr};
                    cmdWrite <= uartCmdWrite;
                    cmdWriteData <= {8'h0, uartCmdWriteData};
                    cmdTrigger <= 1;
                    // Reset our flag so we know when we receive the data
                    uartCmdReadDataValid <= 0;
                    // Next stage
                    uartCmdStage <= uartCmdStage+1;
                end
                
                // ## Wait for command to complete...
                6: begin
                    // Writing data case: wait until the RAM controller accepts the command
                    if (uartCmdWrite) begin
                        // Skip sending the byte we read in the write case
                        if (cmdReady) uartCmdStage <= uartCmdStage+3;
                    
                    // Reading data case: wait until the data is available
                    end else begin
                        if (uartCmdReadDataValid) begin
                            // // TODO: remove
                            // if (cmdAddr == 8'h42) begin
                            //     uartCmdReadData <= 8'h42;
                            // end
                            uartCmdStage <= uartCmdStage+1;
                        end
                    end
                end
                
                // ## Send the byte that we read
                7: begin
                    // Transmit the high nibble as ASCII-hex
        			uartTxByte <= HexASCIIFromNibble(uartCmdReadData[7:4]);
        			uartTransmit <= 1;
                    uartCmdStage <= uartCmdStage+1;
                end
                
                8: begin
                    // Transmit the low nibble as ASCII-hex
        			uartTxByte <= HexASCIIFromNibble(uartCmdReadData[3:0]);
        			uartTransmit <= 1;
                    uartCmdStage <= uartCmdStage+1;
                end
                
                // ## Finish by sending a newline
                9: begin
        			uartTxByte <= 13;
        			uartTransmit <= 1;
                    uartCmdStage <= uartCmdStage+1;
                end
                
                10: begin
        			uartTxByte <= 10;
        			uartTransmit <= 1;
                    uartCmdStage <= 0;
                end
                endcase
            end
        end
    end
endmodule

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"
`include "4012mt48lc16m16a2/mt48lc16m16a2.v"

module IceboardTest_SDRAMReadWriteViaUARTSim(
    output logic        ledRed,

    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_udqm,
    output logic        sdram_ldqm,
    inout logic[15:0]   sdram_dq
);

    logic clk12mhz;

    IceboardTest_SDRAMReadWriteViaUART iceboardSDRAMTest(
        .clk12mhz(clk12mhz),
        .ledRed(ledRed),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_udqm(sdram_udqm),
        .sdram_ldqm(sdram_ldqm),
        .sdram_dq(sdram_dq)
    );

    mt48lc8m16a2 sdram(
        .Clk(sdram_clk),
        .Dq(sdram_dq),
        .Addr(sdram_a),
        .Ba(sdram_ba),
        .Cke(sdram_cke),
        .Cs_n(sdram_cs_),
        .Ras_n(sdram_ras_),
        .Cas_n(sdram_cas_),
        .We_n(sdram_we_),
        .Dqm({sdram_udqm, sdram_ldqm})
    );

//    mt48lc16m16a2 sdram(
//        .Clk(sdram_clk),
//        .Dq(sdram_dq),
//        .Addr({1'b0, sdram_a}),
//        .Ba(sdram_ba),
//        .Cke(sdram_cke),
//        .Cs_n(sdram_cs_),
//        .Ras_n(sdram_ras_),
//        .Cas_n(sdram_cas_),
//        .We_n(sdram_we_),
//        .Dqm({sdram_udqm, sdram_ldqm})
//    );

    initial begin
        $dumpfile("IceboardTest_SDRAMReadWriteViaUART.vcd");
        $dumpvars(0, IceboardTest_SDRAMReadWriteViaUARTSim);

        #10000000;
        $finish;
    end

    initial begin
        clk12mhz = 0;
        forever begin
            clk12mhz = !clk12mhz;
            #42;
        end
    end
endmodule

`endif

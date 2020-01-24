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
    wire uartReceiving;
    wire uartTransmitting;
    
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
        .is_receiving(uartReceiving),      // Low when receive line is idle
        .is_transmitting(uartTransmitting),// Low when transmit line is idle
        .recv_error()                       // Indicates error in receiving packet.
    );
    
    logic[2:0]      uartStage;
    
    logic[63:0]     uartDataIn;
    logic[15:0]     uartDataInCount;
    logic           uartDataInEcho;
    
    logic[128:0]    uartDataOut;
    logic[15:0]     uartDataOutCount;
    
    logic[15:0]     uartReadData;
    logic           uartReadDataValid;
    
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
            uartStage <= 0;
            uartTransmit <= 0;
            uartDataInCount <= 0;
            uartDataInEcho <= 1;
            uartDataOutCount <= 0;
            uartReadDataValid <= 0;
        
        end else begin
            // By default we're not transmitting
            uartTransmit <= 0;
            
            // Disable cmdTrigger once the RAM controller accepts the command
            if (cmdReady) begin
                cmdTrigger <= 0;
            end
            
            if (cmdReadDataValid) begin
                uartReadData <= cmdReadData;
                uartReadDataValid <= 1;
            end
            
            // Wait until active transmissions complete
            if (!uartTransmit && !uartTransmitting) begin
                if (uartDataOutCount > 0) begin
        			uartTxByte <= uartDataOut[(8*uartDataOutCount)-1 -: 8];
                    uartTransmit <= 1;
        			uartDataOutCount <= uartDataOutCount-1;
                
                end else if (uartDataInCount > 0) begin
                    if (uartReceived) begin
                        uartDataIn <= (uartDataIn<<8)|uartRxByte;
                        uartDataInCount <= uartDataInCount-1;
                        
                        // Echo typed character
                        if (uartDataInEcho) begin
                            uartTxByte <= uartRxByte;
                            uartTransmit <= 1;
                        end
                    end
                
                end else begin
                    // Go to the next uartStage by default
                    uartStage <= (uartStage<6 ? uartStage+1 : 0);
                    
                    // Reset our echo state by default
                    uartDataInEcho <= 1;
                    
                    case (uartStage)
                    
                    // Wait for command
                    0: begin
                        uartDataInCount <= 1; // Load a byte for the command
                        uartDataInEcho <= 0;
                    end
                    
                    // Load command, wait for address
                    1: begin
                        cmdWrite <= (uartRxByte=="w");
                        
                        // Echo a "w" or "r"
                        uartDataOut <= (uartRxByte=="w" ? "w" : "r");
            			uartDataOutCount <= 1;
                        
                        uartDataInCount <= 6; // Load 6 bytes of address (each byte is a hex nibble)
                    end
                    
                    // Load address, and if we're writing, wait for the value to write
                    2: begin
                        
                        // Echo a "="
                        uartDataOut <= "=";
            			uartDataOutCount <= 1;
                        
                        cmdAddr <= {
                            NibbleFromHexASCII(uartDataIn[(8*6)-1 -: 8]),
                            NibbleFromHexASCII(uartDataIn[(8*5)-1 -: 8]),
                            NibbleFromHexASCII(uartDataIn[(8*4)-1 -: 8]),
                            NibbleFromHexASCII(uartDataIn[(8*3)-1 -: 8]),
                            NibbleFromHexASCII(uartDataIn[(8*2)-1 -: 8]),
                            NibbleFromHexASCII(uartDataIn[(8*1)-1 -: 8])
                        };

                        // If we're writing, get the data to write
                        if (cmdWrite) uartDataInCount <= 4; // Load 4 bytes of data (each byte is a hex nibble)
                    end
                    
                    // Issue command to the RAM controller
                    3: begin
                        if (cmdWrite) begin
                            cmdWriteData <= {
                                NibbleFromHexASCII(uartDataIn[(8*4)-1 -: 8]),
                                NibbleFromHexASCII(uartDataIn[(8*3)-1 -: 8]),
                                NibbleFromHexASCII(uartDataIn[(8*2)-1 -: 8]),
                                NibbleFromHexASCII(uartDataIn[(8*1)-1 -: 8])
                            };
                        end
                        
                        cmdTrigger <= 1;
                        // Reset our flag so we know when we receive the data
                        uartReadDataValid <= 0;
                    end
                    
                    // Wait for command to complete
                    4: begin
                        // Stall until the RAM controller accepts our command
                        // (We reset cmdTrigger above, when cmdReady fires)
                        if (cmdTrigger) uartStage <= uartStage;
                        // If we're reading, stall until we have the data
                        else if (!cmdWrite && !uartReadDataValid) uartStage <= uartStage;
                    end
                    
                    // If we were reading, output the read data
                    5: begin
                        if (!cmdWrite) begin
                            uartDataOut <= {
                                HexASCIIFromNibble(uartReadData[15:12]),
                                HexASCIIFromNibble(uartReadData[11:8]),
                                HexASCIIFromNibble(uartReadData[7:4]),
                                HexASCIIFromNibble(uartReadData[3:0])
                            };
                            uartDataOutCount <= 4; // Output 4 bytes
                        end
                    end
                    
                    // Send a newline
                    6: begin
                        uartDataOut <= "\r\n";
                        uartDataOutCount <= 2;
                    end
                    endcase
                end
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

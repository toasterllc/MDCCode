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
    
    logic[2:0]  stage;
    
    logic[47:0] dataIn;
    logic[2:0]  dataInCount;
    logic       dataInEcho;
    
    logic[31:0] dataOut;
    logic[2:0]  dataOutCount;
    
    logic[15:0] readData;
    logic       readDataValid;
    
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
            stage <= 0;
            uartTransmit <= 0;
            dataInCount <= 0;
            dataInEcho <= 1;
            dataOutCount <= 0;
            readDataValid <= 0;
        
        end else begin
            // By default we're not transmitting
            uartTransmit <= 0;
            
            // Disable cmdTrigger once the RAM controller accepts the command
            if (cmdReady) begin
                cmdTrigger <= 0;
            end
            
            if (cmdReadDataValid) begin
                readData <= cmdReadData;
                readDataValid <= 1;
            end
            
            // Wait until active transmissions complete
            if (!uartTransmit && !is_transmitting) begin
                if (dataOutCount > 0) begin
        			uartTxByte <= dataOut[7:0];
                    uartTransmit <= 1;
                    
                    dataOut <= dataOut>>8;
        			dataOutCount <= dataOutCount-1;
                
                end else if (dataInCount > 0) begin
                    if (uartReceived) begin
                        dataIn <= (dataIn<<8)|uartRxByte;
                        dataInCount <= dataInCount-1;
                        
                        // Echo typed character
                        if (dataInEcho) begin
                            uartTxByte <= uartRxByte;
                            uartTransmit <= 1;
                        end
                    end
                
                end else begin
                    // Go to the next stage by default
                    stage <= (stage<6 ? stage+1 : 0);
                    
                    // Reset our echo state by default
                    dataInEcho <= 1;
                    
                    case (stage)
                    
                    // Wait for command
                    0: begin
                        dataInCount <= 1; // Load a byte for the command
                        dataInEcho <= 0;
                    end
                    
                    // Load command, wait for address
                    1: begin
                        cmdWrite <= (uartRxByte=="w");
                        
                        // Echo a "w" or "r"
                        dataOut <= (uartRxByte=="w" ? "w" : "r");
            			dataOutCount <= 1;
                        
                        dataInCount <= 6; // Load 6 bytes of address (each byte is a hex nibble)
                    end
                    
                    // Load address, and if we're writing, wait for the value to write
                    2: begin
                        
                        // Echo a "="
                        dataOut <= "=";
            			dataOutCount <= 1;
                        
                        cmdAddr <= {
                            NibbleFromHexASCII(dataIn[(8*6)-1 -: 8]),
                            NibbleFromHexASCII(dataIn[(8*5)-1 -: 8]),
                            NibbleFromHexASCII(dataIn[(8*4)-1 -: 8]),
                            NibbleFromHexASCII(dataIn[(8*3)-1 -: 8]),
                            NibbleFromHexASCII(dataIn[(8*2)-1 -: 8]),
                            NibbleFromHexASCII(dataIn[(8*1)-1 -: 8])
                        };

                        // If we're writing, get the data to write
                        if (cmdWrite) dataInCount <= 4; // Load 4 bytes of data (each byte is a hex nibble)
                    end
                    
                    // Issue command to the RAM controller
                    3: begin
                        if (cmdWrite) begin
                            cmdWriteData <= {
                                NibbleFromHexASCII(dataIn[(8*4)-1 -: 8]),
                                NibbleFromHexASCII(dataIn[(8*3)-1 -: 8]),
                                NibbleFromHexASCII(dataIn[(8*2)-1 -: 8]),
                                NibbleFromHexASCII(dataIn[(8*1)-1 -: 8])
                            };
                        end
                        
                        cmdTrigger <= 1;
                        // Reset our flag so we know when we receive the data
                        readDataValid <= 0;
                    end
                    
                    // Wait for command to complete
                    4: begin
                        // Stall until the RAM controller accepts our command
                        // (We reset cmdTrigger above, when cmdReady fires)
                        if (cmdTrigger) stage <= stage;
                        // If we're reading, stall until we have the data
                        else if (!cmdWrite && !readDataValid) stage <= stage;
                    end
                    
                    // If we were reading, output the read data
                    5: begin
                        if (!cmdWrite) begin
                            dataOut <= {
                                HexASCIIFromNibble(readData[3:0]),
                                HexASCIIFromNibble(readData[7:4]),
                                HexASCIIFromNibble(readData[11:8]),
                                HexASCIIFromNibble(readData[15:12])
                            };
                            dataOutCount <= 4; // Output 4 bytes
                        end
                    end
                    
                    // Send a newline
                    6: begin
                        dataOut <= "\r\n";
                        dataOutCount <= 2;
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

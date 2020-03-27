`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../uart.v"
`include "../SDRAMController.v"

`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

module Top(
    input wire          clk12mhz,
    
    output reg[7:0]     led = 0,
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq,
    
    input wire          uart_rx,
    output wire         uart_tx
);
    // 24 MHz clock
    localparam ClockFrequency = 24000000;
    wire clk;
    wire rst;
    ClockGen #(
        .FREQ(ClockFrequency),
		.DIVR(0),
		.DIVF(63),
		.DIVQ(5),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst(rst));
    
    localparam AddrWidth = 16;
    localparam DataWidth = 16;
    localparam AddrCount = 'h10000;
    
    wire                  cmdReady;
    reg                   cmdTrigger = 0;
    reg[AddrWidth-1:0]    cmdAddr = 0;
    reg                   cmdWrite = 0;
    reg[DataWidth-1:0]    cmdWriteData = 0;
    wire[DataWidth-1:0]   cmdReadData;
    wire                  cmdReadDataValid;
    
    // wire didRefresh;
    // assign led[7:0] = {8{didRefresh}};
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr({9'b0, cmdAddr}),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        
        .ram_clk(ram_clk),
        .ram_cke(ram_cke),
        .ram_ba(ram_ba),
        .ram_a(ram_a),
        .ram_cs_(ram_cs_),
        .ram_ras_(ram_ras_),
        .ram_cas_(ram_cas_),
        .ram_we_(ram_we_),
        .ram_dqm(ram_dqm),
        .ram_dq(ram_dq)
        
        // .didRefresh(didRefresh)
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
        .rx(uart_rx),                // Incoming serial line
        .tx(uart_tx),                // Outgoing serial line
        .transmit(uartTransmit),              // Signal to transmit
        .tx_byte(uartTxByte),                // Byte to transmit
        .received(uartReceived),              // Indicated that a byte has been received
        .rx_byte(uartRxByte),                // Byte received
        .is_receiving(uartReceiving),      // Low when receive line is idle
        .is_transmitting(uartTransmitting),// Low when transmit line is idle
        .recv_error()                       // Indicates error in receiving packet.
    );
    
    reg[2:0]      uartStage = 0;
    
    reg[63:0]     uartDataIn = 0;
    reg[15:0]     uartDataInCount = 0;
    reg           uartDataInSuppress = 0;
    
    reg[32*8-1:0] uartDataOut = 0;
    reg[15:0]     uartDataOutCount = 0;
    
    reg[15:0]     uartReadData = 0;
    reg           uartReadDataValid = 0;
    
    function [7:0] HexASCIIFromNibble;
        input [3:0] n;
        HexASCIIFromNibble = (n<10 ? 8'd48+n : 8'd97-8'd10+n);
    endfunction
    
    function [3:0] NibbleFromHexASCII;
        input [7:0] n;
        NibbleFromHexASCII = (n>=97 ? n-97+10 : n-48);
    endfunction
    
    reg[0:0] init = 0;
    always @(posedge clk) begin
        // Set our default state if the current command was accepted
        if (cmdReady) cmdTrigger <= 0;
        
        // By default we're not transmitting
        uartTransmit <= 0;
        
        // Initialize all memory to 0
        if (!(&init)) begin
            if (!cmdWrite) begin
                cmdTrigger <= 1;
                cmdAddr <= 0;
                cmdWrite <= 1;
                // cmdWriteData <= 16'h0;
                cmdWriteData <= 16'h4444;
                // cmdWriteData <= 16'hFFFF;
            
            // The SDRAM controller accepted the command, so transition to the next state
            end else if (cmdReady) begin
                if (cmdAddr != AddrCount-1) begin
                    $display("Initializing 0x%x=0x%x", cmdAddr+1, 16'hFFFF-(cmdAddr+1));
                    
                    cmdTrigger <= 1;
                    cmdAddr <= cmdAddr+1;
                    cmdWrite <= 1;
                    // cmdWriteData <= 16'h0;
                    cmdWriteData <= 16'h4444;
                    // cmdWriteData <= 16'hFFFF;
                end else begin
                    // Next stage
                    init <= init+1;
                end
            end
        
        end else begin
            led <= 8'hFF;
            
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
                        if (!uartDataInSuppress) begin
                            uartTxByte <= uartRxByte;
                            uartTransmit <= 1;
                        end
                    end
            
                end else begin
                    // Go to the next uartStage by default
                    uartStage <= (uartStage<6 ? uartStage+1 : 0);
                
                    // Reset our echo state by default
                    uartDataInSuppress <= 0;
                
                    case (uartStage)
                
                    // Wait for command
                    0: begin
                        uartDataInCount <= 1; // Load a byte for the command
                        uartDataInSuppress <= 1;
                    end
                
                    // Load command, wait for address
                    1: begin
                        cmdWrite <= (uartRxByte=="w");
                    
                        // Echo a "w" or "r"
                        uartDataOut <= (uartRxByte=="w" ? "w" : "r");
            			uartDataOutCount <= 1;
                    
                        uartDataInCount <= 4; // Load 4 bytes of address (each byte is a hex nibble)
                    end
                
                    // Load address, and if we're writing, wait for the value to write
                    2: begin
                    
                        // Echo a "="
                        uartDataOut <= "=";
            			uartDataOutCount <= 1;
                    
                        cmdAddr <= {
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
    
`ifdef SIM
    mobile_sdr sdram(
        .clk(ram_clk),
        .cke(ram_cke),
        .addr(ram_a),
        .ba(ram_ba),
        .cs_n(ram_cs_),
        .ras_n(ram_ras_),
        .cas_n(ram_cas_),
        .we_n(ram_we_),
        .dq(ram_dq),
        .dqm(ram_dqm)
    );

    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
        // #1000000000;
        // $finish;
    end
`endif
endmodule

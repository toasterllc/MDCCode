`timescale 1ns/1ps
`include "../SDRAMController.v"
`include "../uart.v"

module Random9(
    input logic clk, rst, next,
    output logic[8:0] q
);
    always @(posedge clk)
        if (rst) q <= 1;
        // Feedback polynomial for N=9: x^9 + x^5 + 1
        else if (next) q <= {q[7:0], q[9-1] ^ q[5-1]};
endmodule

module Random16(
    input logic clk, rst, next,
    output logic[15:0] q
);
    always @(posedge clk)
        if (rst) q <= 1;
        // Feedback polynomial for N=16: x^16 + x^15 + x^13 + x^4 + 1
        else if (next) q <= {q[14:0], q[16-1] ^ q[15-1] ^ q[13-1] ^ q[4-1]};
endmodule

module Random23(
    input logic clk, rst, next,
    output logic[22:0] q,
    output logic wrapped
);
    always @(posedge clk)
        if (rst) begin
            q <= 1;
            wrapped <= 0;
        end
        // Feedback polynomial for N=23: x^23 + x^18 + 1
        else if (next) begin
            q <= {q[21:0], q[23-1] ^ q[18-1]};
            if (q == 1) wrapped <= !wrapped;
        end
endmodule

//module Random9(
//    input logic clk, rst, next,
//    output logic[8:0] q
//);
//    always @(posedge clk)
//        if (rst) q <= 0;
//        else if (next) q <= q+1;
//endmodule
//
//module Random16(
//    input logic clk, rst, next,
//    output logic[15:0] q
//);
//    always @(posedge clk)
//        if (rst) q <= 0;
//        else if (next) q <= q+1;
//endmodule
//
//module Random23(
//    input logic clk, rst, next,
//    output logic[22:0] q
//);
//    always @(posedge clk)
//        if (rst) q <= 0;
//        else if (next) q <= q+1;
//endmodule

function [15:0] DataFromAddress;
    input [22:0] addr;
    // DataFromAddress = {9'h1B5, addr[22:16]} ^ ~(addr[15:0]);
    // DataFromAddress = addr[22:7];
    DataFromAddress = addr[15:0];
    // DataFromAddress = 0;
endfunction

module IceboardTest_SDRAMReadWriteRandomly(
    input logic         clk12mhz,
    
    output logic[7:0]   leds,
    
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
    
    `ifdef SIM
    initial clkDivider = 0;
    `endif
    
    logic clk;
    
    // localparam ClockFrequency = 12000000;       // 12 MHz
    // assign clk = clk12mhz;
    //
    // localparam ClockFrequency =  6000000;     // 6 MHz
    // assign clk = clkDivider[0];
    //
    // localparam ClockFrequency =  3000000;     // 3 MHz
    // assign clk = clkDivider[1];
    //
    // localparam ClockFrequency =  1500000;     // 1.5 MHz
    // assign clk = clkDivider[2];
    //
    localparam ClockFrequency =   750000;     // .75 MHz
    assign clk = clkDivider[3];
    //
    // localparam ClockFrequency =   375000;     // .375 MHz     This frequency is too slow -- the RAM controller doesn't have enough time to do anything except refresh
    // assign clk = clkDivider[4];
    
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
    
    `ifdef SIM
    initial rstCounter = 0;
    `endif
    
    localparam AddrWidth = 23;
    localparam AddrCount = 'h800000;
    localparam AddrCountLimit = AddrCount;
    // localparam AddrCountLimit = AddrCount/1024; // 32k words
    // localparam AddrCountLimit = AddrCount/8192; // 1k words
    localparam DataWidth = 16;
    localparam MaxEnqueuedReads = 10;
    localparam StatusOK = 1;
    localparam StatusFailed = 0;
    
    localparam ModeIdle     = 2'h0;
    localparam ModeRead     = 2'h1;
    localparam ModeWrite    = 2'h2;
    
    logic                   cmdReady;
    logic                   cmdTrigger;
    logic[AddrWidth-1:0]    cmdAddr;
    logic                   cmdWrite;
    logic[DataWidth-1:0]    cmdWriteData;
    logic[DataWidth-1:0]    cmdReadData;
    logic                   cmdReadDataValid;
    
    logic needInit;
    logic status;
    logic[(AddrWidth*MaxEnqueuedReads)-1:0] enqueuedReadAddrs, nextEnqueuedReadAddrs;
    logic[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount, nextEnqueuedReadCount;
    
    logic[AddrWidth-1:0] currentReadAddr;
    assign currentReadAddr = enqueuedReadAddrs[AddrWidth-1:0];
    
    logic[1:0] mode;
    logic[AddrWidth-1:0] modeCounter;
    
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
    
    logic[8:0] random9;
    logic random9Next;
    Random9 random9Gen(.clk(clk), .rst(rst), .next(random9Next), .q(random9));
    
    logic[15:0] random16;
    logic random16Next;
    Random16 random16Gen(.clk(clk), .rst(rst), .next(random16Next), .q(random16));
    
    logic wrapped;
    assign leds[7] = wrapped;
    
    logic[22:0] random23;
    logic random23Next;
    Random23 random23Gen(.clk(clk), .rst(rst), .next(random23Next), .q(random23), .wrapped(wrapped));
    
    logic[22:0] randomAddr;
    assign randomAddr = random23&(AddrCountLimit-1);
    
    
    
    
    
    
    
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
    
    logic[32*8-1:0] uartDataOut;
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
    
    
    
    
    logic[DataWidth-1:0] expectedReadData;
    assign expectedReadData = DataFromAddress(currentReadAddr);
    
    logic[DataWidth-1:0] prevReadData;
    assign prevReadData = DataFromAddress(currentReadAddr-1);
    
    logic[DataWidth-1:0] nextReadData;
    assign nextReadData = DataFromAddress(currentReadAddr+1);
    
    
    
    
    always @(posedge clk) begin
        // Set our default state
        if (cmdReady) cmdTrigger <= 0;
        
        random9Next <= 0;
        random16Next <= 0;
        random23Next <= 0;
        
        if (rst) begin
            needInit <= 1;
            status <= StatusOK;
            
            cmdTrigger <= 0;
            cmdAddr <= 0;
            cmdWrite <= 0;
            cmdWriteData <= 0;
            
            enqueuedReadAddrs <= 0;
            enqueuedReadCount <= 0;
            
            nextEnqueuedReadAddrs <= 0;
            nextEnqueuedReadCount <= 0;
            
            mode <= ModeIdle;
            modeCounter <= 0;
            
            uartStage <= 0;
            uartTransmit <= 0;
            uartDataInCount <= 0;
            uartDataInEcho <= 1;
            uartDataOutCount <= 0;
            uartReadDataValid <= 0;
        
        // Initialize memory to known values
        end else if (needInit) begin
            if (!cmdWrite) begin
                cmdTrigger <= 1;
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= DataFromAddress(0);
            
            // The SDRAM controller accepted the command, so transition to the next state
            end else if (cmdReady) begin
                if (cmdAddr < AddrCountLimit-1) begin
//                if (cmdAddr < 'h7FFFFF) begin
//                if (cmdAddr < 'hFF) begin
                    cmdTrigger <= 1;
                    cmdAddr <= cmdAddr+1;
                    cmdWrite <= 1;
                    cmdWriteData <= DataFromAddress(cmdAddr+1);
                    
                    `ifdef SIM
                        if (!(cmdAddr % 'h1000)) begin
                            $display("Initializing memory: %h", cmdAddr);
                        end
                    `endif
                
                end else begin
                    // Next stage
                    needInit <= 0;
                end
            end
        end
        
        else if (status == StatusOK) begin
            nextEnqueuedReadAddrs = enqueuedReadAddrs;
            nextEnqueuedReadCount = enqueuedReadCount;
            
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (nextEnqueuedReadCount > 0) begin
                    // Verify that the data read out is what we expect
//                    if ((cmdReadData|1'b1) !== (DataFromAddress(currentReadAddr)|1'b1)) begin
                    if (cmdReadData !== expectedReadData) begin
                        `ifdef SIM
                            $error("Read invalid data; (wanted: 0x%h=0x%h, got: 0x%h=0x%h)", currentReadAddr, DataFromAddress(currentReadAddr), currentReadAddr, cmdReadData);
                        `endif
                        
                        status <= StatusFailed;
                        // leds[6:0] <= 7'b1111111;
                        
                        uartDataOut <= {
                            HexASCIIFromNibble(currentReadAddr[22:20]),
                            HexASCIIFromNibble(currentReadAddr[19:16]),
                            HexASCIIFromNibble(currentReadAddr[15:12]),
                            HexASCIIFromNibble(currentReadAddr[11:8]),
                            HexASCIIFromNibble(currentReadAddr[7:4]),
                            HexASCIIFromNibble(currentReadAddr[3:0]),
                            
                            "E",
                            HexASCIIFromNibble(expectedReadData[15:12]),
                            HexASCIIFromNibble(expectedReadData[11:8]),
                            HexASCIIFromNibble(expectedReadData[7:4]),
                            HexASCIIFromNibble(expectedReadData[3:0]),
                            
                            "G",
                            HexASCIIFromNibble(cmdReadData[15:12]),
                            HexASCIIFromNibble(cmdReadData[11:8]),
                            HexASCIIFromNibble(cmdReadData[7:4]),
                            HexASCIIFromNibble(cmdReadData[3:0]),
                            
                            "P",
                            HexASCIIFromNibble(prevReadData[15:12]),
                            HexASCIIFromNibble(prevReadData[11:8]),
                            HexASCIIFromNibble(prevReadData[7:4]),
                            HexASCIIFromNibble(prevReadData[3:0]),
                            
                            "N",
                            HexASCIIFromNibble(nextReadData[15:12]),
                            HexASCIIFromNibble(nextReadData[11:8]),
                            HexASCIIFromNibble(nextReadData[7:4]),
                            HexASCIIFromNibble(nextReadData[3:0]),
                            
                            "\r\n"
                        };
                        
            			uartDataOutCount <= 28;
                    end
                    
                    nextEnqueuedReadAddrs = nextEnqueuedReadAddrs >> AddrWidth;
                    nextEnqueuedReadCount = nextEnqueuedReadCount-1;
                
                // Something's wrong if we weren't expecting data and we got some
                end else begin
                    `ifdef SIM
                        $error("Received data when we didn't expect any");
                    `endif
                    
                    status <= StatusFailed;
                    // leds[6:0] <= 7'b0001111;
                    uartDataOut <= "BAD2";
        			uartDataOutCount <= 4;
                end
            end
            
            // Current command was accepted: prepare a new command
            if (cmdReady) begin
                case (mode)
                // We're idle: accept a new mode
                ModeIdle: begin
                    // Nop
                    if (random16 < 1*'h3333) begin
                        `ifdef SIM
                            $display("Nop");
                        `endif
                    end
                    
                    // Read
                    else if (random16 < 2*'h3333) begin
                        `ifdef SIM
                            $display("Read: %h", randomAddr);
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= randomAddr;
                        cmdWrite <= 0;
                        
                        nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|(randomAddr<<(AddrWidth*nextEnqueuedReadCount));
                        nextEnqueuedReadCount = nextEnqueuedReadCount+1;
                        
                        mode <= ModeIdle;
                        random23Next <= 1;
                    end
                    
                    // Read sequential (start)
                    else if (random16 < 3*'h3333) begin
                        `ifdef SIM
                            $display("ReadSeq: %h[%h]", randomAddr, random9);
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= randomAddr;
                        cmdWrite <= 0;
                        
                        nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|(randomAddr<<(AddrWidth*nextEnqueuedReadCount));
                        nextEnqueuedReadCount = nextEnqueuedReadCount+1;
                        
                        mode <= ModeRead;
                        modeCounter <= random9;
                        random9Next <= 1;
                        random23Next <= 1;
                    end
                    
                    // Read all (start)
                    // We want this to be rare so only check for 1 value
                    else if (random16 < 3*'h3333+'h100) begin
                        `ifdef SIM
                            $display("ReadAll");
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= 0;
                        cmdWrite <= 0;
                        
                        nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|(0<<(AddrWidth*nextEnqueuedReadCount));
                        nextEnqueuedReadCount = nextEnqueuedReadCount+1;
                        
                        mode <= ModeRead;
                        modeCounter <= AddrCountLimit-1;
                    end
                    
                    // Write
                    else if (random16 < 4*'h3333) begin
                        `ifdef SIM
                            $display("Write: %h", randomAddr);
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= randomAddr;
                        cmdWrite <= 1;
                        cmdWriteData <= DataFromAddress(randomAddr);
                        
                        mode <= ModeIdle;
                        random23Next <= 1;
                    end
                    
                    // Write sequential (start)
                    else begin
                        `ifdef SIM
                            $display("WriteSeq: %h[%h]", randomAddr, random9);
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= randomAddr;
                        cmdWrite <= 1;
                        cmdWriteData <= DataFromAddress(randomAddr);
                        
                        mode <= ModeWrite;
                        modeCounter <= random9;
                        random9Next <= 1;
                        random23Next <= 1;
                    end
                    
                    random16Next <= 1;
                end
                
                // Read (continue)
                ModeRead: begin
                    if (modeCounter>0 && (cmdAddr+1)<AddrCountLimit) begin
                        cmdTrigger <= 1;
                        cmdAddr <= cmdAddr+1;
                        cmdWrite <= 0;
                        
                        nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|((cmdAddr+1)<<(AddrWidth*nextEnqueuedReadCount));
                        nextEnqueuedReadCount = nextEnqueuedReadCount+1;
                        
                        modeCounter <= modeCounter-1;
                    
                    end else mode <= ModeIdle;
                end
                
                // Write (continue)
                ModeWrite: begin
                    if (modeCounter>0 && (cmdAddr+1)<AddrCountLimit) begin
                        cmdTrigger <= 1;
                        cmdAddr <= cmdAddr+1;
                        cmdWrite <= 1;
                        cmdWriteData <= DataFromAddress(cmdAddr+1);
                        
                        modeCounter <= modeCounter-1;
                    
                    end else mode <= ModeIdle;
                end
                endcase
            end
            
            enqueuedReadAddrs <= nextEnqueuedReadAddrs;
            enqueuedReadCount <= nextEnqueuedReadCount;
        
        // Something went wrong -- allow access via UART
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

`ifdef SIM

`include "../4062mt48lc8m16a2/mt48lc8m16a2.v"
`include "../4012mt48lc16m16a2/mt48lc16m16a2.v"

module IceboardTest_SDRAMReadWriteRandomlySim(
    output logic[7:0]   leds,

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

    IceboardTest_SDRAMReadWriteRandomly iceboardSDRAMTest(
        .clk12mhz(clk12mhz),
        .leds(leds),
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
//        $dumpfile("top.vcd");
//        $dumpvars(0, IceboardTest_SDRAMReadWriteRandomlySim);

//        #10000000;
//        #200000000;
//        #2300000000;
//        $finish;
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

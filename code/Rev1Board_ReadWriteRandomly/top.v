`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../SDRAMController.v"
`include "../uart.v"

`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

module Random6(
    input wire clk, next,
    output reg[5:0] q = 0
);
    always @(posedge clk)
        if (q == 0) q <= 1;
        // Feedback polynomial for N=6: x^6 + x^5 + 1
        else if (next) q <= {q[4:0], q[6-1] ^ q[5-1]};
endmodule

module Random16(
    input wire clk, next,
    output reg[15:0] q = 0
);
    always @(posedge clk)
        if (q == 0) q <= 1;
        // Feedback polynomial for N=16: x^16 + x^15 + x^13 + x^4 + 1
        else if (next) q <= {q[14:0], q[16-1] ^ q[15-1] ^ q[13-1] ^ q[4-1]};
endmodule

module Random25(
    input wire clk, next,
    output reg[24:0] q = 0,
    output reg[24:0] counter = 0,
    output reg wrapped
);
    always @(posedge clk)
        if (q == 0) begin
            q <= 1;
            wrapped <= 0;
        end
        // Feedback polynomial for N=25: x^25 + x^22 + 1
        else if (next) begin
            q <= {q[23:0], q[25-1] ^ q[22-1]};
            if (q == 1) wrapped <= !wrapped;
            counter <= counter+1;
        end
endmodule

module Top(
    input wire          clk12mhz,
    
    output wire[7:0]    led,
    
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
    function [15:0] DataFromAddr;
        input [24:0] addr;
        DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
       // DataFromAddr = addr[15:0];
    endfunction
    
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
    // localparam ClockFrequency =   750000;     // .75 MHz
    // assign clk = clkDivider[3];
    //
    // localparam ClockFrequency =   375000;     // .375 MHz     This frequency is too slow -- the RAM controller doesn't have enough time to do anything except refresh
    // assign clk = clkDivider[4];
    
    localparam AddrWidth = 25;
    localparam AddrCount = 'h2000000;
    // localparam AddrCountLimit = AddrCount;
    // localparam AddrCountLimit = AddrCount/1024; // 32k words
    localparam AddrCountLimit = AddrCount/8192; // 4k words
    localparam DataWidth = 16;
    localparam MaxEnqueuedReads = 10;
    localparam StatusOK = 0;
    localparam StatusFailed = 1;
    
    localparam ModeIdle     = 2'h0;
    localparam ModeRead     = 2'h1;
    localparam ModeWrite    = 2'h2;
    
    wire                    cmdReady;
    reg                     cmdTrigger = 0;
    reg[AddrWidth-1:0]      cmdAddr = 0;
    reg                     cmdWrite = 0;
    reg[DataWidth-1:0]      cmdWriteData = 0;
    wire[DataWidth-1:0]     cmdReadData;
    wire                    cmdReadDataValid;
    
    reg init = 0 /* synthesis syn_keep=1 */; // TODO: figure out if we need syn_keep=1 for `init`. Synplify is removing `init`...
    reg status = StatusOK /* synthesis syn_keep=1 */; // syn_keep is necessary to prevent Synplify optimization from removing -- "removing sequential instance ..."
    reg[(AddrWidth*MaxEnqueuedReads)-1:0] enqueuedReadAddrs = 0, nextEnqueuedReadAddrs = 0;
    reg[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount = 0, nextEnqueuedReadCount = 0;
    
    wire[AddrWidth-1:0] currentReadAddr = enqueuedReadAddrs[AddrWidth-1:0];
    
    reg[1:0] mode = ModeIdle;
    reg[AddrWidth-1:0] modeCounter = 0;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
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
    );
    
    wire[5:0] random6;
    reg random6Next = 0;
    Random6 random6Gen(.clk(clk), .next(random6Next), .q(random6));
    
    wire[15:0] random16;
    reg random16Next = 0;
    Random16 random16Gen(.clk(clk), .next(random16Next), .q(random16));
    
    wire wrapped;
    assign led[7] = wrapped;
    
    wire[24:0] random25;
    wire[24:0] random25Counter;
    reg random25Next = 0;
    Random25 random25Gen(.clk(clk), .next(random25Next), .q(random25), .counter(random25Counter), .wrapped(wrapped));
    
    wire[24:0] randomAddr = random25&(AddrCountLimit-1);
    
    
    
    
    
    
    
    // UART stuff
    reg uartTransmit = 0;
    reg [7:0] uartTxByte = 0;
    wire uartReceived;
    wire [7:0] uartRxByte;
    wire uartReceiving;
    wire uartTransmitting;
    reg uartTransmittingOld = 0;
    
    uart #(
        .baud_rate(9600),                   // The baud rate in kilobits/s
        .sys_clk_freq(ClockFrequency)       // The master clock frequency
    )
    uart0(
        .clk(clk),                          // The master clock for this module
        .rst(rst),                          // Synchronous reset
        .rx(uart_rx),                       // Incoming serial line
        .tx(uart_tx),                       // Outgoing serial line
        .transmit(uartTransmit),            // Signal to transmit
        .tx_byte(uartTxByte),               // Byte to transmit
        .received(uartReceived),            // Indicated that a byte has been received
        .rx_byte(uartRxByte),               // Byte received
        .is_receiving(uartReceiving),       // Low when receive line is idle
        .is_transmitting(uartTransmitting), // Low when transmit line is idle
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
    
    
    
    
    wire[DataWidth-1:0] expectedReadData = DataFromAddr(currentReadAddr);
    wire[DataWidth-1:0] prevReadData = DataFromAddr(currentReadAddr-1);
    wire[DataWidth-1:0] nextReadData = DataFromAddr(currentReadAddr+1);
    
    
    
    
    always @(posedge clk) begin
        // Set our default state
        if (cmdReady) cmdTrigger <= 0;
        
        random6Next <= 0;
        random16Next <= 0;
        random25Next <= 0;
        
        uartTransmit <= 0;
        
        // Transmit another UART byte if data is available, and we're not currently transmitting
        if (!uartTransmit && !uartTransmitting && uartDataOutCount>0) begin
			uartTxByte <= uartDataOut[(8*uartDataOutCount)-1 -: 8];
            uartTransmit <= 1;
			uartDataOutCount <= uartDataOutCount-1;
        end
        
        if (random25Counter!=25'h0 && !(random25Counter%25'h100000)) begin
            if (!uartDataOutCount) begin
                uartDataOut <= {
                    HexASCIIFromNibble({3'b0, random25Counter[24]}),
                    HexASCIIFromNibble(random25Counter[23:20]),
                    HexASCIIFromNibble(random25Counter[19:16]),
                    HexASCIIFromNibble(random25Counter[15:12]),
                    HexASCIIFromNibble(random25Counter[11:8]),
                    HexASCIIFromNibble(random25Counter[7:4]),
                    HexASCIIFromNibble(random25Counter[3:0]),
                
                    "\r\n"
                };
            
                uartDataOutCount <= 9;
            end
        end
        
        // Initialize memory to known values
        if (!init) begin
            if (!cmdWrite) begin
                cmdTrigger <= 1;
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= DataFromAddr(0);
            
            // The SDRAM controller accepted the command, so transition to the next state
            end else if (cmdReady) begin
                if (cmdAddr < AddrCountLimit-1) begin
//                if (cmdAddr < 'h7FFFFF) begin
//                if (cmdAddr < 'hFF) begin
                    cmdTrigger <= 1;
                    cmdAddr <= cmdAddr+1;
                    cmdWrite <= 1;
                    cmdWriteData <= DataFromAddr(cmdAddr+1);
                    
                    `ifdef SIM
                        if (!(cmdAddr % 'h1000)) begin
                            $display("Initializing memory: %h", cmdAddr);
                        end
                    `endif
                
                end else begin
                    // Next stage
                    init <= 1;
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
//                    if ((cmdReadData|1'b1) !== (DataFromAddr(currentReadAddr)|1'b1)) begin
                    if (cmdReadData !== expectedReadData) begin
                        `ifdef SIM
                            $error("Read invalid data; (wanted: 0x%h=0x%h, got: 0x%h=0x%h)", currentReadAddr, DataFromAddr(currentReadAddr), currentReadAddr, cmdReadData);
                        `endif
                        
                        status <= StatusFailed;
                        // led[6:0] <= 7'b1111111;
                        
                        uartDataOut <= {
                            HexASCIIFromNibble({3'b0, currentReadAddr[24]}),
                            HexASCIIFromNibble(currentReadAddr[23:20]),
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
                        
            			uartDataOutCount <= 29;
                    end
                    
                    nextEnqueuedReadAddrs = nextEnqueuedReadAddrs >> AddrWidth;
                    nextEnqueuedReadCount = nextEnqueuedReadCount-1;
                
                // Something's wrong if we weren't expecting data and we got some
                end else begin
                    `ifdef SIM
                        $error("Received data when we didn't expect any");
                    `endif
                    
                    status <= StatusFailed;
                    // led[6:0] <= 7'b0001111;
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
                        random25Next <= 1;
                    end
                    
                    // Read sequential (start)
                    else if (random16 < 3*'h3333) begin
                        `ifdef SIM
                            $display("ReadSeq: %h[%h]", randomAddr, random6);
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= randomAddr;
                        cmdWrite <= 0;
                        
                        nextEnqueuedReadAddrs = nextEnqueuedReadAddrs|(randomAddr<<(AddrWidth*nextEnqueuedReadCount));
                        nextEnqueuedReadCount = nextEnqueuedReadCount+1;
                        
                        mode <= ModeRead;
                        modeCounter <= random6;
                        random6Next <= 1;
                        random25Next <= 1;
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
                        cmdWriteData <= DataFromAddr(randomAddr);
                        
                        mode <= ModeIdle;
                        random25Next <= 1;
                    end
                    
                    // Write sequential (start)
                    else begin
                        `ifdef SIM
                            $display("WriteSeq: %h[%h]", randomAddr, random6);
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= randomAddr;
                        cmdWrite <= 1;
                        cmdWriteData <= DataFromAddr(randomAddr);
                        
                        mode <= ModeWrite;
                        modeCounter <= random6;
                        random6Next <= 1;
                        random25Next <= 1;
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
                        cmdWriteData <= DataFromAddr(cmdAddr+1);
                        
                        modeCounter <= modeCounter-1;
                    
                    end else mode <= ModeIdle;
                end
                endcase
            end
            
            enqueuedReadAddrs <= nextEnqueuedReadAddrs;
            enqueuedReadCount <= nextEnqueuedReadCount;
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
        #1000000000;
        $finish;
    end
`endif
endmodule

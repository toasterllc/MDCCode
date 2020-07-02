`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../AFIFO.v"
`include "../SDRAMController.v"

module Debug(
    input wire          clk,
    
    output wire[7:0]    cmd,
    output wire         cmdReady,
    input wire          cmdTrigger,
    
    input wire[7:0]     msg,
    input wire[8:0]     msgLen,
    output reg          msgTrigger = 0,
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do
);
    // ====================
    // In queue `inq`
    // ====================
    reg inq_writeTrigger = 0;
    reg[7:0] inq_writeData = 0;
    wire inq_writeOK;
    AFIFO #(.Width(8), .Size(8)) inq(
        .rclk(clk),
        .r(cmdTrigger),
        .rd(cmd),
        .rok(cmdReady),
        
        .wclk(debug_clk),
        .w(debug_cs && inq_writeTrigger),
        .wd(inq_writeData),
        .wok(inq_writeOK)
    );
    
    // ====================
    // Out queue `outq`
    // ====================
    reg outq_readTrigger=0, outq_writeTrigger=0;
    wire[7:0] outq_readData;
    reg[7:0] outq_writeData = 0;
    wire outq_readOK, outq_writeOK;
    AFIFO #(.Width(8), .Size(8)) outq(
        .rclk(debug_clk),
        .r(debug_cs && outq_readTrigger),
        .rd(outq_readData),
        .rok(outq_readOK),
        
        .wclk(clk),
        .w(outq_writeTrigger),
        .wd(outq_writeData),
        .wok(outq_writeOK)
    );
    
    // ====================
    // Command+response handling
    // ====================
    // assign msgTrigger = (msgLen && outq_writeTrigger && outq_writeOK);
    reg[1:0] msgState = 0;
    always @(posedge clk) begin
        case (msgState)
        // Send command (byte 0)
        0: begin
            if (msgLen) begin
                outq_writeData <= msg;
                outq_writeTrigger <= 1;
                msgState <= 1;
            end
        end
        
        // Send message length (byte 1)
        1: begin
            if (outq_writeOK) begin
                outq_writeData <= msgLen-1;
                outq_writeTrigger <= 1;
                msgTrigger <= 1;
                msgState <= 2;
            end
        end
        
        // Delay state while the next message byte is triggered
        2: begin
            msgTrigger <= 0;
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
                
                if (msgLen) begin
                    msgState <= 3;
                end else begin
                    msgState <= 0;
                end
            end
        end
        
        // Send the message payload
        3: begin
            outq_writeData <= msg;
            outq_writeTrigger <= 1;
            msgTrigger <= 1;
            msgState <= 2;
        end
        endcase
    end
    
    
    
    
    
    
    
    
    
    // ====================
    // Data relay/shifting (debug_di->inq, outq->debug_do)
    // ====================
    reg[1:0] inCmdState = 0;
    reg[8:0] inCmd = 0; // High bit is the end-of-data sentinel, and isn't transmitted
    reg[1:0] outMsgState = 0;
    reg[8:0] outMsgShiftReg = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    assign debug_do = outMsgShiftReg[8];
    always @(posedge debug_clk) begin
        if (debug_cs) begin
            case (inCmdState)
            0: begin
                // Initialize `inCmd` as if it was originally initialized to 1,
                // so that after the first clock it contains the sentinel and
                // the first bit of data.
                inCmd <= {1'b1, debug_di};
                inCmdState <= 1;
            end
            
            1: begin
                if (inq_writeTrigger && !inq_writeOK) begin
                    // TODO: handle dropped commands
                end
                
                if (inCmd[8]) begin
                    // Only pass along non-zero commands.
                    // Otherwise checking for data (by using 1-byte NOP commands) could produce
                    // 2-byte output data (cmd=Nop, payloadLen=0), which would break the design.
                    if (inCmd[7:0]) begin
                        inq_writeTrigger <= 1;
                        inq_writeData <= inCmd[7:0];
                    end
                    inCmd <= {1'b1, debug_di};
                
                end else begin
                    inq_writeTrigger <= 0;
                    inCmd <= (inCmd<<1)|debug_di;
                end
            end
            endcase
            
            case (outMsgState)
            0: begin
                // Initialize `outMsgShiftReg` as if it was originally initialized to 1,
                // so that after the first clock cycle it contains the sentinel.
                outMsgShiftReg <= 2'b10;
                outMsgState <= 3;
            end
            
            1: begin
                outMsgShiftReg <= outMsgShiftReg<<1;
                outq_readTrigger <= 0;
                
                // If we successfully read a byte, shift it out
                if (outq_readOK) begin
                    outMsgShiftReg <= {outq_readData, 1'b1}; // Add sentinel to the end
                    outMsgState <= 2;
                
                // Otherwise shift out 2 zero bytes (cmd=Nop, payloadLen=0)
                end else begin
                    outMsgShiftReg <= 1;
                    outMsgState <= 3;
                end
            end
            
            // Continue shifting out a byte
            2: begin
                outMsgShiftReg <= outMsgShiftReg<<1;
                if (outMsgShiftReg[6:0] == 7'b1000000) begin
                    outq_readTrigger <= 1;
                    outMsgState <= 1;
                end
            end
            
            // Shift out 2 zero bytes
            3: begin
                outMsgShiftReg <= outMsgShiftReg<<1;
                if (outMsgShiftReg[7:0] == 8'b10000000) begin
                    outMsgShiftReg <= 1;
                    outMsgState <= 2;
                end
            end
            endcase
        end
    end
    
    
    
    
    
    
    
    
    // // ====================
    // // Data relay/shifting (debug_di->inq, outq->debug_do)
    // // ====================
    // reg[7:0] inCmd = 0;
    // wire inCmdReady = inCmd[7];
    // reg[8:0] outMsgShiftReg = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    // assign debug_do = outMsgShiftReg[8];
    // always @(posedge debug_clk) begin
    //     if (debug_cs) begin
    //         // Reset stuff by default
    //         inq_writeTrigger <= 0;
    //         outq_readTrigger <= 0;
    //
    //         if (inq_writeTrigger && !inq_writeOK) begin
    //             // TODO: handle dropped commands
    //         end
    //
    //         // ## Incoming command relay: debug_di -> inq
    //         // Continue shifting in command
    //         if (!inCmdReady) begin
    //             inCmd <= (inCmd<<1)|debug_di;
    //
    //         // Enqueue the command into `inq`
    //         end else begin
    //             inq_writeTrigger <= 1;
    //             inq_writeData <= inCmd;
    //
    //             // Start shifting the next command
    //             inCmd <= debug_di;
    //         end
    //
    //         // ## Outgoing message relay: outq -> debug_do
    //         // Continue shifting out the current data, if there's still data remaining
    //         if (outMsgShiftReg[6:0]) begin
    //             outMsgShiftReg <= outMsgShiftReg<<1;
    //
    //             // Trigger a read on the correct clock cycle
    //             if (outMsgShiftReg[6:0] == 15'b1000000) begin
    //                 outq_readTrigger <= 1;
    //             end
    //
    //         // Otherwise load the next byte, if there's one available
    //         end else if (outq_readTrigger && outq_readOK) begin
    //             outMsgShiftReg <= {outq_readData, 1'b1}; // Add sentinel to the end
    //
    //         end else begin
    //             // outMsgShiftReg initialization must be as if it was originally
    //             // initialized to 1, so after the first clock cycle it should be 1<<1.
    //             if (!outMsgShiftReg) outMsgShiftReg <= 1<<1;
    //             else outMsgShiftReg <= 1;
    //         end
    //     end
    // end
endmodule





module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0,
    
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
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do
);
    // ====================
    // Clock PLL (54.750 MHz)
    // ====================
    localparam ClockFrequency = 54750000;
    wire clk;
    ClockGen #(
        .FREQ(ClockFrequency),
		.DIVR(0),
		.DIVF(72),
		.DIVQ(4),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    
    
    
    
    
    
    // ====================
    // SDRAM controller
    // ====================
    localparam RAM_Size = 'h2000000;
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;

    // RAM controller
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  ram_cmdWriteData = 0;
    wire[RAM_DataWidth-1:0] ram_cmdReadData;
    wire                    ram_cmdReadDataValid;

    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),

        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(ram_cmdReadData),
        .cmdReadDataValid(ram_cmdReadDataValid),

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
    
    
    
    
    
    
    
    
    
    
    
    
    // ====================
    // Debug I/O
    // ====================
    localparam CmdNop       = 8'h00;
    localparam CmdLEDOff    = 8'h80;
    localparam CmdLEDOn     = 8'h81;
    localparam CmdReadMem   = 8'h82;
    
    wire[7:0] debug_cmd;
    wire debug_cmdReady;
    reg debug_cmdTrigger = 0;
    
    reg[7:0] debug_msg = 0;
    reg[8:0] debug_msgLen = 0;
    wire debug_msgTrigger;
    
    reg[7:0] cmd = 0;
    
    Debug debug(
        .clk(clk),
        
        .cmd(debug_cmd),
        .cmdReady(debug_cmdReady),
        .cmdTrigger(debug_cmdTrigger),
        
        .msg(debug_msg),
        .msgLen(debug_msgLen),
        .msgTrigger(debug_msgTrigger),
        
        .debug_clk(debug_clk),
        .debug_cs(debug_cs),
        .debug_di(debug_di),
        .debug_do(debug_do)
    );
    
    
    
    
    
    
    
    
    
    
    
    
    // ====================
    // Main
    // ====================
    function [15:0] DataFromAddr;
        input [24:0] addr;
        // DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
        DataFromAddr = addr[15:0];
        // DataFromAddr = 16'hFFFF;
        // DataFromAddr = 16'h0000;
        // DataFromAddr = 16'h7832;
    endfunction
    
    function [63:0] Min;
        input [63:0] a;
        input [63:0] b;
        Min = (a < b ? a : b);
    endfunction
    
    reg[3:0] state = 0;
    reg[7:0] mem[255:0];
    reg[7:0] memLen = 0;
    reg[7:0] memCounter = 0;
    reg[7:0] memCounterRecv = 0;
    
    reg[7:0] cmd = CmdNop;
    always @(posedge clk) begin
        case (state)
        
        // Initialize the SDRAM
        0: begin
            if (!ram_cmdTrigger) begin
                ram_cmdTrigger <= 1;
                ram_cmdAddr <= 0;
                ram_cmdWrite <= 1;
                ram_cmdWriteData <= DataFromAddr(0);
            
            end else if (ram_cmdReady) begin
                ram_cmdAddr <= ram_cmdAddr+1;
                ram_cmdWriteData <= DataFromAddr(ram_cmdAddr+1);
                
                if (ram_cmdAddr == RAM_Size-1) begin
                    ram_cmdTrigger <= 0;
                    state <= 1;
                end
            end
        end
        
        // Accept new command
        1: begin
            debug_cmdTrigger <= 1;
            if (debug_cmdTrigger && debug_cmdReady) begin
                cmd <= debug_cmd;
                state <= 2;
            end
        end
        
        // Handle new command
        2: begin
            debug_cmdTrigger <= 0;
            
            // By default go to state 3 next
            state <= 3;
            
            case (cmd)
            default: begin
                debug_msg <= cmd;
                debug_msgLen <= 256;
            end
            
            CmdLEDOff: begin
                led[0] <= 0;
                debug_msg <= cmd;
                debug_msgLen <= 256;
            end
            
            CmdLEDOn: begin
                led[0] <= 1;
                debug_msg <= cmd;
                debug_msgLen <= 256;
            end
            
            CmdReadMem: begin
                ram_cmdAddr <= 0;
                ram_cmdWrite <= 0;
                state <= 4;
            end
            endcase
        end
        
        // Wait until the message is sent
        3: begin
            if (debug_msgTrigger) begin
                debug_msg <= debug_msgLen-1;
                debug_msgLen <= debug_msgLen-1;
                
                if (debug_msgLen == 1) begin
                    state <= 1;
                end
            end
        end
        
        // Start reading memory
        4: begin
            ram_cmdTrigger <= 1;
            memCounter <= Min(8'h7F, RAM_Size-ram_cmdAddr);
            memCounterRecv <= Min(8'h7F, RAM_Size-ram_cmdAddr);
            memLen <= 8'h00;
            state <= 5;
        end
        
        // Continue reading memory
        5: begin
            // Handle the read being accepted
            if (ram_cmdReady && memCounter) begin
                ram_cmdAddr <= (ram_cmdAddr+1)&(RAM_Size-1); // Prevent ram_cmdAddr from overflowing
                memCounter <= memCounter-1;
                
                // Stop reading
                if (memCounter == 1) begin
                    ram_cmdTrigger <= 0;
                end
            end
            
            // Writing incoming data into `mem`
            if (ram_cmdReadDataValid) begin
                mem[memLen] <= ram_cmdReadData[7:0];
                mem[memLen+1] <= ram_cmdReadData[15:8];
                memLen <= memLen+2;
                memCounterRecv <= memCounterRecv-1;
                
                // Next state after we've received all the bytes
                if (memCounterRecv == 1) begin
                    state <= 6;
                end
            end
        end
        
        // Start sending the data
        6: begin
            debug_msg <= CmdReadMem;
            debug_msgLen <= memLen+1;
            memCounter <= 0;
            state <= 7;
        end
        
        // Send the data
        7: begin
            // Continue sending data
            if (debug_msgTrigger) begin
                debug_msg <= mem[memCounter];
                debug_msgLen <= debug_msgLen-1;
                memCounter <= memCounter+1;
                
                // We're finished with this chunk.
                // Start on the next chunk, or stop if we've read everything.
                if (debug_msgLen == 1) begin
                    if (ram_cmdAddr == 0) begin
                        state <= 1;
                    end else begin
                        state <= 4;
                    end
                end
            end
        end
        endcase
    end
endmodule

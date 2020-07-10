`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../AFIFO.v"
`include "../SDRAMController.v"

module Debug #(
    // Max payload length (bytes)
    // *** Code needs to be updated below if this is changed!
    // *** See serialIn_payloadCounter case statement.
    parameter MsgMaxPayloadLen = 5
)(
    input wire                              clk,
    
    output wire[7:0]                        msgIn_type,
    output wire[7:0]                        msgIn_payloadLen,
    output wire[(MsgMaxPayloadLen*8)-1:0]   msgIn_payload,
    output wire                             msgIn_ready,
    input wire                              msgIn_trigger,
    
    input wire[7:0]                         msgOut_type,
    input wire[7:0]                         msgOut_payloadLen,
    input wire[7:0]                         msgOut_payload,
    output reg                              msgOut_payloadTrigger = 0,
    
    input wire                              debug_clk,
    input wire                              debug_cs,
    input wire                              debug_di,
    output wire                             debug_do
);
    localparam MsgHeaderLen = 2; // Message header length (bytes)
    localparam MsgMaxLen = MsgHeaderLen+MsgMaxPayloadLen;
    
    assign msgIn_type = inq_readData[0*8+:8];
    assign msgIn_payloadLen = inq_readData[1*8+:8];
    assign msgIn_payload = inq_readData[2*8+:MsgMaxPayloadLen*8];
    assign msgIn_ready = inq_readOK;
    
    // ====================
    // In queue `inq`
    // ====================
    wire inq_rclk = clk;
    wire inq_readOK;
    wire inq_readTrigger = msgIn_trigger;
    wire[(MsgMaxLen*8)-1:0] inq_readData;
    wire inq_wclk = debug_clk;
    reg inq_writeTrigger = 0;
    wire[(MsgMaxLen*8)-1:0] inq_writeData = serialIn_msg;
    wire inq_writeOK;
    AFIFO #(.Width(MsgMaxLen*8), .Size(4)) inq(
        .rclk(inq_rclk),
        .r(inq_readTrigger),
        .rd(inq_readData),
        .rok(inq_readOK),
        .wclk(inq_wclk),
        .w(debug_cs && inq_writeTrigger),
        .wd(inq_writeData),
        .wok(inq_writeOK)
    );
    
    // ====================
    // Out queue `outq`
    // ====================
    wire outq_rclk = debug_clk;
    reg outq_readTrigger = 0;
    wire[7:0] outq_readData;
    wire outq_readOK;
    wire outq_wclk = clk;
    reg outq_writeTrigger = 0;
    reg[7:0] outq_writeData = 0;
    wire outq_writeOK;
    AFIFO #(.Width(8), .Size(4)) outq(
        .rclk(outq_rclk),
        .r(debug_cs & outq_readTrigger),
        .rd(outq_readData),
        .rok(outq_readOK),
        .wclk(outq_wclk),
        .w(outq_writeTrigger),
        .wd(outq_writeData),
        .wok(outq_writeOK)
    );
    
    // ====================
    // Message output / `clk` domain
    // ====================
    reg[2:0] msgOut_state = 0;
    always @(posedge clk) begin
        case (msgOut_state)
        // Send message type (byte 0)
        0: begin
            if (msgOut_type) begin
                outq_writeData <= msgOut_type;
                outq_writeTrigger <= 1;
                msgOut_state <= 1;
            end
        end
    
        // Send payload length (byte 1)
        1: begin
            if (outq_writeOK) begin
                outq_writeData <= msgOut_payloadLen;
                outq_writeTrigger <= 1;
                msgOut_state <= 2;
            end
        end
    
        // Delay while payload length is written
        2: begin
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
            
                // Trigger the initial payload byte, or provide the final payload trigger,
                // depending on whether there's payload data.
                msgOut_payloadTrigger <= 1;
                if (!msgOut_payloadLen) begin
                    msgOut_state <= 3;
                end else begin
                    msgOut_state <= 4;
                end
            end
        end
    
        // Delay before returning to first state
        3: begin
            msgOut_payloadTrigger <= 0;
            msgOut_state <= 0;
        end
    
        // Delay while first payload byte is loaded
        4: begin
            msgOut_payloadTrigger <= 0;
            msgOut_state <= 5;
        end
    
        5: begin
            outq_writeData <= msgOut_payload;
            outq_writeTrigger <= 1;
            msgOut_payloadTrigger <= 1;
            if (msgOut_payloadLen) begin
                msgOut_state <= 6;
            end else begin
                msgOut_state <= 7;
            end
        end
    
        // Delay while previous byte is written
        6: begin
            msgOut_payloadTrigger <= 0;
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
                msgOut_state <= 5;
            end
        end
    
        // Delay while final byte is written and client resets, before returning to first state
        7: begin
            msgOut_payloadTrigger <= 0;
            if (outq_writeOK) begin
                outq_writeTrigger <= 0;
                msgOut_state <= 0;
            end
        end
        endcase
    end
    
    
    
    
    
    
    
    
    
    // ====================
    // Serial IO / `debug_clk` domain
    // ====================
    reg[1:0] serialIn_state = 0;
    reg[8:0] serialIn_shiftReg = 0; // High bit is the end-of-data sentinel, and isn't transmitted
    wire[7:0] serialIn_byte = serialIn_shiftReg[7:0];
    wire serialIn_byteReady = serialIn_shiftReg[8];
    reg[(MsgMaxLen*8)-1:0] serialIn_msg = 0;
    wire[7:0] serialIn_msgType = serialIn_msg[0*8+:8];
    wire[7:0] serialIn_payloadLen = serialIn_msg[1*8+:8];
    reg[7:0] serialIn_payloadCounter = 0;
    reg[1:0] serialOut_state = 0;
    reg[8:0] serialOut_shiftReg = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    assign debug_do = serialOut_shiftReg[8];
    always @(posedge debug_clk) begin
        if (!debug_cs) begin
            serialIn_msg <= 0;
            serialIn_payloadCounter <= 0;
            serialIn_shiftReg <= 0;
            serialIn_state <= 0;
            serialOut_shiftReg <= 0;
            serialOut_state <= 0;
            
            inq_writeTrigger <= 0;
            outq_readTrigger <= 0;
        
        end else begin
            if (serialIn_byteReady) begin
                serialIn_shiftReg <= {1'b1, debug_di};
            end else begin
                serialIn_shiftReg <= (serialIn_shiftReg<<1)|debug_di;
            end
        
            case (serialIn_state)
            0: begin
                // Initialize `serialIn_shiftReg` as if it was originally initialized to 1,
                // so that after the first clock it contains the sentinel and
                // the first bit of data.
                serialIn_shiftReg <= {1'b1, debug_di};
                serialIn_state <= 1;
            end
        
            // if (inq_writeTrigger && !inq_writeOK) begin
            //     // TODO: handle dropped bytes
            // end
        
            1: begin
                inq_writeTrigger <= 0; // Clear from state 3
                if (serialIn_byteReady) begin
                    // Only transition states if we have a valid message type.
                    // This way, new messages can occur at any byte boundary,
                    // instead of every other byte if we required both
                    // message type + payload length for every transmission.
                    if (serialIn_byte) begin
                        serialIn_msg[0*8+:8] <= serialIn_byte;
                        serialIn_state <= 2;
                    end
                end
            end
        
            2: begin
                if (serialIn_byteReady) begin
                    serialIn_msg[1*8+:8] <= serialIn_byte;
                    serialIn_payloadCounter <= 0;
                    serialIn_state <= 3;
                end
            end
        
            3: begin
                if (serialIn_payloadCounter < serialIn_payloadLen) begin
                    if (serialIn_byteReady) begin
                        // Only write while serialIn_payloadCounter < MsgMaxPayloadLen to prevent overflow.
                        if (serialIn_payloadCounter < MsgMaxPayloadLen) begin
                            case (serialIn_payloadCounter)
                            0: serialIn_msg[(0+2)*8+:8] <= serialIn_byte;
                            1: serialIn_msg[(1+2)*8+:8] <= serialIn_byte;
                            2: serialIn_msg[(2+2)*8+:8] <= serialIn_byte;
                            3: serialIn_msg[(3+2)*8+:8] <= serialIn_byte;
                            4: serialIn_msg[(4+2)*8+:8] <= serialIn_byte;
                            endcase
                        end
                        serialIn_payloadCounter <= serialIn_payloadCounter+1;
                    end
            
                end else begin
                    // $display("Received message: msgType=%0d, payloadLen=%0d", serialIn_msgType, serialIn_payloadLen);
                    // Only transmit non-nop messages
                    if (serialIn_msgType) begin
                        inq_writeTrigger <= 1;
                    end
                    serialIn_state <= 1;
                end
            end
            endcase
        
            case (serialOut_state)
            0: begin
                // Initialize `serialOut_shiftReg` as if it was originally initialized to 1,
                // so that after the first clock cycle it contains the sentinel.
                serialOut_shiftReg <= 2'b10;
                serialOut_state <= 2;
            end
        
            1: begin
                serialOut_shiftReg <= serialOut_shiftReg<<1;
                outq_readTrigger <= 0;
            
                // If we successfully read a byte, shift it out
                if (outq_readOK) begin
                    serialOut_shiftReg <= {outq_readData, 1'b1}; // Add sentinel to the end
            
                // Otherwise shift out a zero byte
                end else begin
                    serialOut_shiftReg <= {8'b0, 1'b1}; // Add sentinel to the end
                end
            
                serialOut_state <= 2;
            end
        
            // Continue shifting out a byte
            2: begin
                serialOut_shiftReg <= serialOut_shiftReg<<1;
                if (serialOut_shiftReg[6:0] == 7'b1000000) begin
                    outq_readTrigger <= 1;
                    serialOut_state <= 1;
                end
            end
            endcase
        end
    end
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
    
    output wire         pix_i2c_clk,
    inout wire          pix_i2c_data,
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do
);
    // ====================
    // Clock PLL (15.938 MHz)
    // ====================
    localparam ClockFrequency = 15938000;
    wire clk;
    ClockGen #(
        .FREQ(ClockFrequency),
        .DIVR(0),
        .DIVF(84),
        .DIVQ(6),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    
    
    
    
    
    // ====================
    // SDRAM controller
    // ====================
    localparam RAM_Size = 'h2000000;
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;
    
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
    // I2C Master
    // ====================
    
    wire[6:0] pix_i2c_cmd_slaveAddr = 7'h20;
    reg pix_i2c_cmd_write = 0;
    reg[15:0] pix_i2c_cmd_regAddr = 0;
    reg[15:0] pix_i2c_cmd_writeData = 0;
    wire[15:0] pix_i2c_cmd_readData;
    reg[1:0] pix_i2c_cmd_dataLen = 0;
    wire pix_i2c_cmd_done;
    wire pix_i2c_cmd_ok;
    
    
    
    
    
    // ====================
    // Debug I/O
    // ====================
    localparam MsgType_SetLED           = 8'h01;
    localparam MsgType_ReadMem          = 8'h02;
    localparam MsgType_PixReg8          = 8'h03;
    localparam MsgType_PixReg16         = 8'h04;
    
    wire[7:0] debug_msgIn_type;
    wire[7:0] debug_msgIn_payloadLen;
    wire[5*8-1:0] debug_msgIn_payload;
    wire debug_msgIn_ready;
    reg debug_msgIn_trigger = 0;
    
    reg[7:0] debug_msgOut_type = 0;
    reg[7:0] debug_msgOut_payloadLen = 0;
    reg[7:0] debug_msgOut_payload = 0;
    wire debug_msgOut_payloadTrigger;
    Debug debug(
        .clk(clk),
        
        .msgIn_type(debug_msgIn_type),
        .msgIn_payloadLen(debug_msgIn_payloadLen),
        .msgIn_payload(debug_msgIn_payload),
        .msgIn_ready(debug_msgIn_ready),
        .msgIn_trigger(debug_msgIn_trigger),
        
        .msgOut_type(debug_msgOut_type),
        .msgOut_payloadLen(debug_msgOut_payloadLen),
        .msgOut_payload(debug_msgOut_payload),
        .msgOut_payloadTrigger(debug_msgOut_payloadTrigger),
        
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
        // DataFromAddr = {addr[24:9]};
        // DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
        DataFromAddr = addr[15:0];
        // DataFromAddr = 16'hFFFF;
        // DataFromAddr = 16'h0000;
        // DataFromAddr = 16'h7832;
        // DataFromAddr = 16'hCAFE;
    endfunction
    
    function [63:0] Min;
        input [63:0] a;
        input [63:0] b;
        Min = (a < b ? a : b);
    endfunction
    
    localparam StateInit        = 0;    // +1
    localparam StateHandleMsg   = 2;    // +2
    localparam StateReadMem     = 5;    // +4
    localparam StatePixReg8     = 10;   // +2
    localparam StatePixReg16    = 13;   // +2
    
    reg[3:0] state = 0;
    reg[7:0] msgInType = 0;
    reg[5*8-1:0] msgInPayload = 0;
    reg[15:0] memTmp = 0;
    reg[15:0] lastMemTmp = 0;
    reg memTmpTrigger = 0;
    reg[15:0] mem[127:0] /* synthesis syn_ramstyle="no_rw_check" */;
    reg[7:0] memLenA = 0;
    reg[7:0] memCounter = 0;
    reg[7:0] memCounterRecv = 0;
    reg[7:0] newCounter = 0;
    always @(posedge clk) begin
        case (state)
        
        // Initialize the SDRAM
        StateInit: begin
            debug_msgIn_trigger <= 0;
            debug_msgOut_payload <= 0;
            debug_msgOut_payloadLen <= 0;
            debug_msgOut_type <= 0;
            lastMemTmp <= 0;
            led <= 0;
            // mem <= 0;
            memCounter <= 0;
            memCounterRecv <= 0;
            memLenA <= 0;
            memTmp <= 0;
            memTmpTrigger <= 0;
            msgInPayload <= 0;
            msgInType <= 0;
            newCounter <= 0;
            pix_i2c_cmd_dataLen <= 0;
            pix_i2c_cmd_regAddr <= 0;
            pix_i2c_cmd_write <= 0;
            pix_i2c_cmd_writeData <= 0;
            ram_cmdAddr <= 0;
            ram_cmdTrigger <= 0;
            ram_cmdWrite <= 0;
            ram_cmdWriteData <= 0;
            
            state <= StateInit+1;
        end
        
        StateInit+1: begin
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
                    state <= StateHandleMsg;
                end
            end
        end
        
        
        
        
        
        
        
        // Accept new command
        StateHandleMsg: begin
            led[0] <= 1;
            debug_msgIn_trigger <= 1;
            if (debug_msgIn_trigger && debug_msgIn_ready) begin
                debug_msgIn_trigger <= 0;
                
                msgInType <= debug_msgIn_type;
                msgInPayload <= debug_msgIn_payload;
                
                state <= StateHandleMsg+1;
            end
        end
        
        // Handle new command
        StateHandleMsg+1: begin
            // By default go to StateHandleMsg+2 next
            state <= StateHandleMsg+2;
            
            case (msgInType)
            default: begin
                debug_msgOut_type <= msgInType;
                debug_msgOut_payloadLen <= 0;
            end
            
            MsgType_ReadMem: begin
                ram_cmdAddr <= 0;
                ram_cmdWrite <= 0;
                state <= StateReadMem;
            end
            
            MsgType_SetLED: begin
                $display("MsgType_SetLED: %0d", msgInPayload[0]);
                led[0] <= msgInPayload[0];
                debug_msgOut_type <= MsgType_SetLED;
                debug_msgOut_payloadLen <= 255;
            end
            
            MsgType_PixReg8: begin
                state <= StatePixReg8;
            end
            
            MsgType_PixReg16: begin
                state <= StatePixReg16;
            end
            endcase
        end
        
        // Wait while the message is being sent
        StateHandleMsg+2: begin
            if (debug_msgOut_payloadTrigger) begin
                debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                debug_msgOut_payload <= debug_msgOut_payloadLen;
                if (!debug_msgOut_payloadLen) begin
                    debug_msgOut_type <= MsgType_SetLED;
                    debug_msgOut_payloadLen <= 255;
                    
                    // // Clear `debug_msgOut_type` to prevent another message from being sent.
                    // debug_msgOut_type <= 0;
                    // state <= StateHandleMsg;
                end
            end
        end
        
        
        
        
        
        // Start reading memory
        StateReadMem: begin
            ram_cmdAddr <= 0;
            ram_cmdWrite <= 0;
            lastMemTmp <= 0;
            state <= StateReadMem+1;
        end
        
        StateReadMem+1: begin
            ram_cmdTrigger <= 1;
            memCounter <= Min(8'h7F, RAM_Size-ram_cmdAddr);
            memCounterRecv <= Min(8'h7F, RAM_Size-ram_cmdAddr);
            memLenA <= 8'h00;
            state <= StateReadMem+2;
        end
        
        // Continue reading memory
        StateReadMem+2: begin
            // Handle the read being accepted
            if (ram_cmdReady && memCounter) begin
                ram_cmdAddr <= (ram_cmdAddr+1)&(RAM_Size-1); // Prevent ram_cmdAddr from overflowing
                
                // Stop triggering when we've issued all the read commands
                memCounter <= memCounter-1;
                if (memCounter == 1) begin
                    ram_cmdTrigger <= 0;
                end
            end
            
            if (memTmpTrigger) begin
                memTmpTrigger <= 0;
                
                mem[memLenA] <= memTmp;
                memLenA <= memLenA+1;
                
                if (memTmp && memTmp!=(lastMemTmp+1'b1)) begin
                    led[3] <= 1;
                end
                lastMemTmp <= memTmp;
                
                // Next state after we've received all the bytes
                memCounterRecv <= memCounterRecv-1;
                if (memCounterRecv == 1) begin
                    state <= StateReadMem+3;
                end
            end
            
            // Write incoming data into `memTmp`
            if (ram_cmdReadDataValid) begin
                memTmp <= ram_cmdReadData;
                memTmpTrigger <= 1;
            end
        end
        
        // Start sending the data
        StateReadMem+3: begin
            debug_msgOut_type <= MsgType_ReadMem;
            debug_msgOut_payloadLen <= memLenA<<1; // memLenA*2 for the number of bytes
            newCounter <= 0;
            memLenA <= 0;
            state <= StateReadMem+4;
        end
        
        // Send the data
        StateReadMem+4: begin
            // Continue sending data
            if (debug_msgOut_payloadTrigger) begin
                debug_msgOut_payloadLen <= debug_msgOut_payloadLen-1;
                
                if (debug_msgOut_payloadLen) begin
                    if (!newCounter[0])
                        debug_msgOut_payload <= mem[memLenA][7:0]; // Low byte
                    else
                        debug_msgOut_payload <= mem[memLenA][15:8]; // High byte
                    newCounter <= newCounter+1;
                    memLenA <= (newCounter+1)>>1;
                
                end else begin
                    // We're finished with this chunk.
                    // Clear `debug_msgOut_type` to prevent another message from being sent.
                    debug_msgOut_type <= 0;
                    
                    // Start on the next chunk, or stop if we've read everything.
                    if (ram_cmdAddr == 0) begin
                        state <= StateHandleMsg;
                    end else begin
                        state <= StateReadMem+1;
                    end
                end
            end
        end
        endcase
    end
    
endmodule

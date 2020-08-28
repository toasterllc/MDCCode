`include "Util.v"
`include "CRC7.v"
`include "CRC16.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

module SDCardController(
    input wire          clk,
    
    // Command port
    input wire          cmd_trigger,
    input wire          cmd_write,
    input wire[31:0]    cmd_addr,       // (2^32)*512 == 2 TB
    input wire[13:0]    cmd_len,        // (2^14)*512 == 8 MB max transfer size
    
    // Data-out port
    output reg[15:0]    dataOut = 0,
    output reg          dataOut_valid = 0,
    
    // SDIO port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
);
    // ====================
    // Pin: sd_clk
    // ====================
    assign sd_clk = clk;
    
    
    
    
    // ====================
    // Pin: sd_cmd
    // ====================
    wire sd_cmdIn;
    wire sd_cmdOut = cmdOut;
    wire sd_cmdOutActive = cmdOutActive;
    SB_IO #(
        .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
        .NEG_TRIGGER(1'b1)
    ) sbio (
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_CLK(clk),
        .OUTPUT_ENABLE(sd_cmdOutActive),
        .D_OUT_0(sd_cmdOut),
        .D_IN_0(sd_cmdIn)
    );
    
    
    
    
    // ====================
    // Pin: sd_dat
    // ====================
    wire[3:0] sd_datIn;
    reg[3:0] sd_datOut = 0;
    reg sd_datOutActive = 0;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
            .NEG_TRIGGER(1'b1)
        ) sbio (
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_CLK(clk),
            .OUTPUT_ENABLE(sd_datOutActive),
            .D_OUT_0(sd_datOut[i]),
            .D_IN_0(sd_datIn[i])
        );
    end
    
    
    
    
    
    
    
    
    // ====================
    // State Machine Registers
    // ====================
    localparam StateIdle        = 0;    // +0
    localparam StateWrite       = 1;    // +0
    localparam StateRead        = 2;    // +3
    reg[3:0] state = 0;
    
    localparam DatStateIdle     = 0;    // +0
    localparam DatStateIn       = 1;    // +4
    localparam DatStateDone     = 6;    // +0
    localparam DatStateError    = 7;    // +0
    reg[3:0] datState = 0;
    
    localparam CMD0 =   6'd0;       // GO_IDLE_STATE
    localparam CMD18 =  6'd18;      // READ_MULTIPLE_BLOCK
    localparam CMD55 =  6'd55;      // APP_CMD
    
    reg cmdInStaged = 0;
    reg[47:0] cmdInReg = 0;
    wire cmdIn = sd_cmdIn;
    wire[3:0] datIn = sd_datIn;
    reg[15:0] datInReg = 0;
    reg[3:0] datInCounter = 0;
    reg[9:0] blockCounter = 0;
    reg[47:0] resp = 0;
    reg respLoad = 0;
    
    reg cmdOutActive = 0;
    reg[47:0] cmdOutReg = 0;
    wire cmdOut = cmdOutReg[47];
    reg[5:0] cmdOutCounter = 0;
    
    reg[31:0] cmdAddr = 0;
    reg[13:0] cmdLen = 0;
    
    
    
    
    // ====================
    // CRC (CMD in)
    // ====================
    // wire[6:0] cmdInCRC;
    // CRC7 CRC7_cmdIn(
    //     .clk(clk),
    //     .rst_(cmdInActive),
    //     .din(cmdInReg[47]),
    //     .dout(),
    //     .doutNext(cmdOutCRC)
    // );
    
    // ====================
    // CRC (CMD out)
    // ====================
    wire[6:0] cmdOutCRC;
    CRC7 CRC7_cmdOut(
        .clk(clk),
        .rst_(cmdOutActive),
        .din(cmdOutReg[47]),
        .dout(),
        .doutNext(cmdOutCRC)
    );
    
    // ====================
    // CRC (DAT[3:0])
    // ====================
    reg datInCRCRst_ = 0;
    wire[15:0] datInCRC[3:0];
    for (i=0; i<4; i=i+1) begin
        CRC16 crc16(
            .clk(clk),
            .rst_(datInCRCRst_),
            .din(datInReg[4+i]),
            .dout(datInCRC[i]),
            .doutNext()
        );
    end
    
    reg[15:0] datIn3CRCReg = 0;
    reg[15:0] datIn2CRCReg = 0;
    reg[15:0] datIn1CRCReg = 0;
    reg[15:0] datIn0CRCReg = 0;
    
    
    
    
    
    // ====================
    // State Machine
    // ====================
    always @(posedge clk) begin
        cmdOutReg <= cmdOutReg<<1;
        cmdOutCounter <= cmdOutCounter-1;
        
        cmdInStaged <= cmdIn;
        cmdInReg <= (cmdInReg<<1)|(cmdOutActive ? 1'b1 : cmdIn);
        
        datInReg <= (datInReg<<4)|{datIn[3], datIn[2], datIn[1], datIn[0]};
        datInCounter <= datInCounter-1;
        
        datIn3CRCReg <= datIn3CRCReg<<1;
        datIn2CRCReg <= datIn2CRCReg<<1;
        datIn1CRCReg <= datIn1CRCReg<<1;
        datIn0CRCReg <= datIn0CRCReg<<1;
        
        dataOut_valid <= 0; // Reset by default
        
        blockCounter <= blockCounter-1;
        
        if (respLoad && !cmdInReg[47]) begin
            resp <= cmdInReg;
            respLoad <= 0;
        end
        
        
        
        
        case (datState)
        DatStateIdle: begin
        end
        
        DatStateIn: begin
            if (!datInReg[0]) begin
                datState <= DatStateIn+1;
            end
        end
        
        DatStateIn+1: begin
            datInCRCRst_ <= 1;
            datInCounter <= 2;
            blockCounter <= 1023;
            datState <= DatStateIn+2;
        end
        
        DatStateIn+2: begin
            if (!datInCounter) begin
                datInCounter <= 3;
                dataOut <= datInReg;
                dataOut_valid <= 1;
            end
            
            if (!blockCounter) begin
                datInCounter <= 16;
                datState <= DatStateIn+3;
            end
        end
        
        // Remember the CRC we calculated
        DatStateIn+3: begin
            datInCRCRst_ <= 0;
            datIn3CRCReg <= datInCRC[3];
            datIn2CRCReg <= datInCRC[2];
            datIn1CRCReg <= datInCRC[1];
            datIn0CRCReg <= datInCRC[0];
            datState <= DatStateIn+4;
            $display("[SD HOST] Received CRCs: %b %b %b %b", datInCRC[3], datInCRC[2], datInCRC[1], datInCRC[0]);
        end
        
        // Check CRC for each DAT line
        DatStateIn+4: begin
            // $display("EXPECTED CRCs: %h, %h, %h, %h", datIn3CRCReg, datIn2CRCReg, datIn1CRCReg, datIn0CRCReg);
            // $display("Our CRC: %h", datIn3CRCReg);
            // Handle invalid CRC
            if (datIn3CRCReg[15]!==datInReg[11] ||
                datIn2CRCReg[15]!==datInReg[10] ||
                datIn1CRCReg[15]!==datInReg[9]  ||
                datIn0CRCReg[15]!==datInReg[8]  ) begin
                // TODO: handle error
                $display("[SD HOST] Bad CRC ❌");
                datState <= DatStateError;
            
            end else if (datInCounter) begin
                $display("[SD HOST] CRC bit valid ✅");
            
            end else begin
                datState <= DatStateDone;
            end 
        end
        
        DatStateDone: begin
        end
        
        DatStateError: begin
        end
        endcase
        
        
        
        
        
        
        
        
        
        
        
        case (state)
        StateIdle: begin
            if (cmd_trigger) begin
                cmdAddr <= cmd_addr;
                cmdLen <= cmd_len;
                state <= (cmd_write ? StateWrite : StateRead);
            end
        end
        
        
        
        
        
        StateWrite: begin
            
        end
        
        
        
        
        
        
        
        StateRead: begin
            $display("[SD HOST] Sending read data: %b", {2'b01, CMD18, cmdAddr, 7'bXXXXXXX, 1'b1});
            cmdOutReg <= {2'b01, CMD18, cmdAddr, 7'b0, 1'b1};
            cmdOutCounter <= 47;
            cmdOutActive <= 1;
            state <= StateRead+1;
        end
        
        StateRead+1: begin
            if (cmdOutCounter == 8) begin
                cmdOutReg[47:41] <= cmdOutCRC;
            
            end else if (!cmdOutCounter) begin
                respLoad <= 1;
                cmdOutActive <= 0;
                datState <= DatStateIn;
                state <= StateRead+2;
            end
        end
        
        StateRead+2: begin
            if (datState == DatStateDone) begin
                state <= StateRead+3;
            end
            
            if (datState == DatStateError) begin
                // TODO: handle error
            end
        end
        
        StateRead+3: begin
            if (resp[47] || resp[46] || !resp[0]) begin
                $display("[SD HOST] Bad start/stop/transmission bit ❌");
                // TODO: handle error

            end else begin
                $display("[SD HOST] Finished reading data");
                state <= StateIdle;
            end

            // $display("DONE");
            // $finish;
        end
        endcase
    end
endmodule

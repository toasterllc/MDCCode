`include "Util.v"
`include "CRC7.v"

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
    // State Machine
    // ====================
    localparam StateIdle        = 0;    // +0
    localparam StateWrite       = 1;    // +0
    localparam StateRead        = 2;    // +4
    reg[3:0] state = 0;
    
    localparam CMD0 =   6'd0;       // GO_IDLE_STATE
    localparam CMD18 =  6'd18;      // READ_MULTIPLE_BLOCK
    localparam CMD55 =  6'd55;      // APP_CMD
    
    reg[47:0] cmdInReg = 0;
    wire cmdIn = sd_cmdIn;
    wire[3:0] datIn = sd_datIn;
    reg[15:0] datInReg = 0;
    reg[2:0] datInCounter = 0;
    reg[7:0] blockCounter = 0;
    reg[47:0] resp = 0;
    
    reg cmdOutActive = 0;
    reg[47:0] cmdOutReg = 0;
    wire cmdOut = cmdOutReg[47];
    reg[5:0] cmdOutCounter = 0;
    
    reg[31:0] cmdAddr = 0;
    reg[13:0] cmdLen = 0;
    
    always @(posedge clk) begin
        cmdOutReg <= cmdOutReg<<1;
        cmdOutCounter <= cmdOutCounter-1;
        
        cmdInReg <= (cmdInReg<<1)|(cmdOutActive ? 1'b1 : cmdIn);
        
        datInReg <= (datInReg<<4)|{datIn[3], datIn[2], datIn[1], datIn[0]};
        datInCounter <= datInCounter-1;
        
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
            cmdOutReg <= {2'b01, CMD18, cmdAddr, 7'b0, 1'b1};
            cmdOutCounter <= 47;
            cmdOutActive <= 1;
            state <= StateRead+1;
        end
        
        StateRead+1: begin
            if (!cmdOutCounter) begin
                cmdOutActive <= 0;
                state <= StateRead+2;
            end
        end
        
        StateRead+2: begin
            // // Wait for response to complete
            // if (!cmdInReg[47]) begin
            //     resp <= cmdInReg;
            // end
            if (!datInReg[0]) begin
                state <= StateRead+3;
            end
        end
        
        StateRead+3: begin
            datInCounter <= 2;
            blockCounter <= 255;
            state <= StateRead+4;
        end
        
        StateRead+4: begin
            dataOut_valid <= 0; // Reset by default
            
            if (!blockCounter) begin
                datInCounter <= 7;
                state <= StateRead+5;
            
            end else if (!datInCounter) begin
                datInCounter <= 3;
                dataOut <= datInReg;
                dataOut_valid <= 1;
                blockCounter <= blockCounter-1;
            end
        end
        
        StateRead+5: begin
            if (!datInCounter) begin
                state <= StateRead+6;
            end
        end
        
        StateRead+6: begin
            if (resp[47] || resp[46] || !resp[0]) begin
                // TODO: handle error
            
            end else begin
                state <= StateIdle;
            end
        end
        endcase
    end
endmodule

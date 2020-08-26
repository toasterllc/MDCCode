`include "Util.v"
`include "CRC7.v"
`include "ClockGen.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

module SDCardController(
    input wire          clk,
    
    // Command port
    input wire          cmd_trigger,
    input wire          cmd_write,
    input wire[31:0]    cmd_addr,       // (2^31)*512 == 256 GB
    input wire[13:0]    cmd_len,        // (2^14)*512 == 8 MB max transfer size
    output wire[15:0]   cmd_dataOut,
    output wire[13:0]   cmd_dataOutLen,
    
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
    reg sd_cmdOut = cmdOut;
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
    
    
    
    
    
    // // ====================
    // // SD Card Initializer
    // // ====================
    // wire init_done;
    // wire init_sd_clk;
    // wire init_sd_cmdIn = sd_cmdIn;
    // wire init_sd_cmdOut;
    // wire init_sd_cmdOutActive;
    // wire[3:0] init_sd_dat = sd_datIn;
    // SDCardInitializer sdinit(
    //     .clk12mhz(clk12mhz),
    //     .done(init_done),
    //
    //     .sd_clk(init_sd_clk),
    //     .sd_cmdIn(init_sd_cmdIn),
    //     .sd_cmdOut(init_sd_cmdOut),
    //     .sd_cmdOutActive(init_sd_cmdOutActive),
    //     .sd_dat(init_sd_dat)
    // );
    //
    //
    //
    //
    //
    // // ====================
    // // `initDone` synchronizer
    // // ====================
    // reg initDone=0, initDoneTmp=0;
    // always @(negedge clk)
    //     {initDone, initDoneTmp} <= {initDoneTmp, init_done};
    
    
    
    
    
    
    
    // ====================
    // State Machine
    // ====================
    localparam StateIdle        = 0;    // +0
    localparam StateWrite       = 1;    // +0
    localparam StateRead        = 2;    // +0
    reg[1:0] state = 0;
    
    localparam CMD0 =   6'd0;       // GO_IDLE_STATE
    localparam CMD18 =  6'd18;      // READ_MULTIPLE_BLOCK
    localparam CMD55 =  6'd55;      // APP_CMD
    
    reg cmdInActive = 0;
    wire cmdIn = sd_cmdIn;
    
    reg cmdOutActive = 0;
    reg[47:0] cmdOutReg = 0;
    wire cmdOut = cmdOutReg[47];
    reg[5:0] cmdOutCounter = 0;
    
    reg[31:0] cmdAddr = 0;
    reg[13:0] cmdLen = 0;
    
    always @(posedge clk) begin
        cmdOutReg <= cmdOutReg<<1;
        cmdOutCounter <= cmdOutCounter-1;
        
        if (cmdInActive) begin
            cmdInReg <= (cmdInReg<<1)|cmdIn;
            cmdInCounter <= cmdInCounter-1;
        end
        
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
            // Wait for response
            if (!cmdInStaged[0]) begin
                cmdInActive <= 1;
                state <= StateRespIn+1;
            end
            
            if (!cmdOutCounter) begin
                cmdOutActive <= 0;
                state <= StateRead+2;
            end
        end
        endcase
    end
endmodule

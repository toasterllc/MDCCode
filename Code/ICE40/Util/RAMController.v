`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

module RAMController #(
    parameter ClkFreq       = 12000000,
    parameter BlockSize     = 2304*1296,
    
    localparam WordWidth    = 16,
    localparam BankWidth    = 2,
    localparam RowWidth     = 13,
    localparam ColWidth     = 10,
    localparam DQMWidth     = 2,
    
    localparam AddrWidth    = BankWidth+RowWidth+ColWidth,
    `define BankBits        AddrWidth-1                     -: BankWidth
    `define RowBits         AddrWidth-BankWidth-1           -: RowWidth
    `define ColBits         AddrWidth-BankWidth-RowWidth-1  -: ColWidth
    
    localparam BlockCount   = (64'b1<<AddrWidth)/BlockSize,
    localparam BlockWidth   = $clog2(BlockCount+1)
)(
    input wire                  clk,            // Clock
    
    // Command port
    output reg                  cmd_ready = 0,  // Ready for new command
    input wire                  cmd_trigger,    // Start the command
    input wire[BlockWidth-1:0]  cmd_block,      // Block index
    input wire                  cmd_write,      // Read (0) or write (1)
    
    // Data port
    output reg                  data_ready = 0, // Reading: `data_read` is valid; writing: `data_write` accepted
    input wire                  data_trigger,   // Only effective if `data_ready`=1
    input wire[WordWidth-1:0]   data_write,     // Data to write
    output reg[WordWidth-1:0]   data_read = 0,  // Data read
    output reg                  data_done = 0,  // Asserted when the end of the block is reached
    
    // RAM port
    output wire                 ram_clk,        // Clock
    output wire                 ram_cke,        // Clock enable
    output wire[BankWidth-1:0]  ram_ba,         // Bank address
    output wire[RowWidth-1:0]   ram_a,          // Address
    output wire                 ram_cs_,        // Chip select
    output wire                 ram_ras_,       // Row address strobe
    output wire                 ram_cas_,       // Column address strobe
    output wire                 ram_we_,        // Write enable
    output wire[DQMWidth-1:0]   ram_dqm,        // Data mask
    inout wire[WordWidth-1:0]   ram_dq          // Data input/output
);
    // Winbond W989D6DB Timing parameters (nanoseconds)
    localparam T_INIT               = 200000;   // Power up initialization time
    localparam T_REFI               = 7812;     // Time between refreshes
    localparam T_RC                 = 68;       // Bank activate to bank activate time (same bank)
    localparam T_RFC                = 72;       // Refresh time
    localparam T_RRD                = 15;       // Row activate to row activate time (different banks)
    localparam T_RAS                = 45;       // Row activate to precharge time (same bank)
    localparam T_RCD                = 18;       // Bank activate to read/write time (same bank)
    localparam T_RP                 = 18;       // Precharge to refresh/row activate (same bank)
    localparam T_WR                 = 15;       // Write recover time
    
    // Timing parameters (clock cycles)
    localparam C_CAS                = 2;        // Column address strobe (CAS) delay
    localparam C_DQZ                = 2;        // (T_DQZ) DQM to data high-impedance during reads delay
    localparam C_MRD                = 2;        // (T_MRD) set mode command to bank activate/refresh command delay
    
    // ras_, cas_, we_
    localparam RAM_Cmd_SetMode          = 3'b000;
    localparam RAM_Cmd_AutoRefresh      = 3'b001;
    localparam RAM_Cmd_PrechargeAll     = 3'b010;
    localparam RAM_Cmd_BankActivate     = 3'b011;
    localparam RAM_Cmd_Write            = 3'b100;
    localparam RAM_Cmd_Read             = 3'b101;
    localparam RAM_Cmd_Nop              = 3'b111;
    
    localparam RAM_DQM_Unmasked         = 0;
    localparam RAM_DQM_Masked           = 1;
    
    function[63:0] DivCeil;
        input[63:0] n;
        input[63:0] d;
        DivCeil = (n+d-1)/d;
    endfunction
    
    // Sub() performs Max(0, a-b)
    function[63:0] Sub;
        input[63:0] a;
        input[63:0] b;
        if (a > b)  Sub = a-b;
        else        Sub = 0;
    endfunction
    
    // Clocks() returns the minimum number of `ClkFreq` clock cycles
    // for >= `t` nanoseconds to elapse. For example, if t=5ns, and
    // the clock period is 3ns, Clocks(t=5,sub=0) will return 2.
    // `sub` is subtracted from that value, with the result clipped to zero.
    function[63:0] Clocks;
        input[63:0] t;
        input[63:0] sub;
        begin
            Clocks = DivCeil(t*ClkFreq, 1000000000);
            if (Clocks >= sub) Clocks = Clocks-sub;
            else Clocks = 0;
        end
    endfunction
    
    function[63:0] Max;
        input[63:0] a;
        input[63:0] b;
        Max = (a > b ? a : b);
    endfunction
    
    // ====================
    // ram_clk
    // ====================
    Delay #(
        .Count(0)
    ) Delay(
        .in(clk),
        .out(ram_clk)
    );
    
    // ====================
    // ram_cke
    // ====================
    reg ramCKE = 0;
    SB_IO #(
        .PIN_TYPE(6'b0101_01)
    ) SB_IO_ram_cke (
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(ram_cke),
        .D_OUT_0(ramCKE)
    );
    
    // ====================
    // ram_ba
    // ====================
    reg[BankWidth-1:0] ramBA = 0;
    genvar i;
    for (i=0; i<BankWidth; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b0101_01)
        ) SB_IO_ram_ba (
            .OUTPUT_CLK(clk),
            .PACKAGE_PIN(ram_ba[i]),
            .D_OUT_0(ramBA[i])
        );
    end
    
    // ====================
    // ram_a
    // ====================
    reg[RowWidth-1:0] ramA = 0;
    for (i=0; i<RowWidth; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b0101_01)
        ) SB_IO_ram_a (
            .OUTPUT_CLK(clk),
            .PACKAGE_PIN(ram_a[i]),
            .D_OUT_0(ramA[i])
        );
    end
    
    // ====================
    // ram_cs_
    // ====================
    assign ram_cs_ = 0;
    
    // ====================
    // ram_ras_, ram_cas_, ram_we_
    // ====================
    reg[2:0] ramCmd = 0;
    SB_IO #(
        .PIN_TYPE(6'b0101_01)
    ) SB_IO_ram_ras_ (
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(ram_ras_),
        .D_OUT_0(ramCmd[2])
    );
    
    SB_IO #(
        .PIN_TYPE(6'b0101_01)
    ) SB_IO_ram_cas_ (
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(ram_cas_),
        .D_OUT_0(ramCmd[1])
    );
    
    SB_IO #(
        .PIN_TYPE(6'b0101_01)
    ) SB_IO_ram_we_ (
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(ram_we_),
        .D_OUT_0(ramCmd[0])
    );
    
    // ====================
    // ram_dqm
    // ====================
    reg ramDQM = 0;
    for (i=0; i<DQMWidth; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b0101_01)
        ) SB_IO_ram_dqm (
            .OUTPUT_CLK(clk),
            .PACKAGE_PIN(ram_dqm[i]),
            .D_OUT_0(ramDQM)
        );
    end
    
    // ====================
    // ram_dq
    // ====================
    reg ramDQOutEn = 0;
    wire[WordWidth-1:0] ramDQOut;
    wire[WordWidth-1:0] ramDQIn;
    for (i=0; i<WordWidth; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_00)
        ) SB_IO_sd_cmd (
            .INPUT_CLK(clk),
            .OUTPUT_CLK(clk),
            .PACKAGE_PIN(ram_dq[i]),
            .OUTPUT_ENABLE(ramDQOutEn),
            .D_OUT_0(ramDQOut[i]),
            .D_IN_0(ramDQIn[i])
        );
    end
    
    reg cmd_saved_trigger = 0;
    reg[BlockWidth-1:0] cmd_saved_block = 0;
    reg cmd_saved_write = 0;
    
    localparam Init_State_Init       = 0;
    localparam Init_State_Delay      = 8;
    
    localparam Cmd_State_Idle           = 0;
    
    localparam Data_State_Idle           = 0;
    localparam Data_State_Write          = 0;
    localparam Data_State_Read           = 0;
    localparam Data_State_Refresh        = 7;
    localparam Data_State_Delay          = 8;
    
    reg init_done = 0;
    reg[3:0] init_state = 0;
    reg[3:0] init_nextState = 0;
    // TODO: verify that this is the correct math, since init_delayCounter is only used in the init states
    // At high clock speeds, Clocks(T_RFC,1) is the largest delay stored in delayCounter.
    // At low clock speeds, C_DQZ+1 is the largest delay stored in delayCounter.
    localparam Init_DelayCounterWidth = Max($clog2(Clocks(T_RFC,1)+1), $clog2(C_DQZ+1+1));
    reg[Init_DelayCounterWidth-1:0] init_delayCounter = 0;
    
    reg[3:0] cmd_state = 0;
    reg[3:0] data_state = 0;
    reg[3:0] data_nextState = 0;
    // TODO: verify that this is the correct math, since data_delayCounter is only used in the init states
    // At high clock speeds, Clocks(T_RFC,1) is the largest delay stored in delayCounter.
    // At low clock speeds, C_DQZ+1 is the largest delay stored in delayCounter.
    localparam Data_DelayCounterWidth = Max($clog2(Clocks(T_RFC,1)+1), $clog2(C_DQZ+1+1));
    reg[Data_DelayCounterWidth-1:0] data_delayCounter = 0;
    localparam Data_RefreshCounterWidth = $clog2(Clocks(T_REFI,1)+1);
    reg[Data_RefreshCounterWidth-1:0] data_refreshCounter = 0;
    
    localparam Data_BankActivateDelay = Max(Max(Max(
        // T_RCD: ensure "bank activate to read/write time".
        // -1 cycle getting to the next state
        Clocks(T_RCD, 1),
        // T_RAS: ensure "row activate to precharge time", ie that we don't
        // CmdPrechargeAll too soon after we activate the bank.
        // -2 cycles since we know that it takes >=2 state transitions from this state
        // to issue CmdPrechargeAll (StateIdle/StateHandleSaved -> StateRead/StateWrite ->
        // StateReadAbort/StateWriteAbort)
        Clocks(T_RAS, 2)),
        // T_RC: ensure "activate bank A to activate bank A time", to ensure that the next
        // bank can't be activated too soon after this bank activation.
        // -3 cycles since we know that it takes >=3 state transitions from this state to
        // reach this state again and issue another CmdBankActivate (StateIdle/StateHandleSaved ->
        // StateRead/StateWrite -> StateReadAbort/StateWriteAbort -> StateIdle/StateHandleSaved)
        Clocks(T_RC, 3)),
        // T_RRD: ensure "activate bank A to activate bank B time", to ensure that the next
        // bank can't be activated too soon after this bank activation.
        // -3 cycles since we know that it takes >=3 state transitions from this state to
        // reach this state again and issue another CmdBankActivate (see explanation for T_RC, above.)
        Clocks(T_RRD, 3));
    
	always @(posedge clk) begin
        init_delayCounter <= init_delayCounter-1;
        data_delayCounter <= data_delayCounter-1;
        // TODO: make sure `Clocks(T_REFI,2)` is right
        data_refreshCounter <= (data_refreshCounter ? data_refreshCounter-1 : Clocks(T_REFI,2));
        if (!data_refreshCounter) begin
            // TODO: save current data_ state so we can restore it after refreshing
            data_state <= Data_StateRefresh;
        end
        
        // Handle cmd_ready
        cmd_ready <= 0; // Reset by default
        cmd_saved_ready <= cmd_ready;
        if (cmd_ready) begin
            cmd_saved_trigger <= cmd_trigger;
            cmd_saved_block <= cmd_block;
            cmd_saved_write <= cmd_write;
        end
        
        // Handle data_ready
        data_ready <= 0; // Reset by default
        data_saved_ready <= data_ready;
        if (data_ready) begin
            data_saved_trigger <= data_trigger;
            data_saved_write <= data_write;
        end
        
        // Reset RAM cmd state
        ramCmd <= RAM_Cmd_Nop;
        ramDQM <= RAM_DQM_Masked;
        ramDQOutEn <= 0;
        
        if (!init_done) begin
            case (state)
            Init_State_Init: begin
                // Initialize registers
                ramCKE <= 0;
                init_delayCounter <= Clocks(T_INIT, 2); // Delay T_INIT; -2 cycles getting to the next state
                init_state <= Init_State_Delay;
                init_nextState <= Init_State_Init+1;
            end
            
            Init_State_Init+1: begin
                // Bring ram_cke high for a bit before issuing commands
                ramCKE <= 1;
                init_delayCounter <= 10; // Delay 10 cycles
                init_state <= Init_State_Delay;
                init_nextState <= Init_State_Init+2;
            end
            
            Init_State_Init+2: begin
                // Precharge all banks
                ramCmd <= RAM_Cmd_PrechargeAll;
                ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
                
                init_delayCounter <= Clocks(T_RP, 2); // Delay T_RP; -2 cycles getting to the next state
                init_state <= Init_State_Delay;
                init_nextState <= Init_State_Init+3;
            end
            
            Init_State_Init+3: begin
                // Autorefresh 1/2
                ramCmd <= RAM_Cmd_AutoRefresh;
                // Wait T_RFC for autorefresh to complete
                // The docs say it takes T_RFC for AutoRefresh to complete, but T_RP must be met
                // before issuing successive AutoRefresh commands. Because T_RFC>T_RP, assume
                // we just have to wait T_RFC.
                init_delayCounter <= Clocks(T_RFC, 2); // Delay T_RFC; -2 cycles getting to the next state
                init_state <= Init_State_Delay;
                init_nextState <= Init_State_Init+4;
            end
            
            Init_State_Init+4: begin
                // Autorefresh 2/2
                ramCmd <= RAM_Cmd_AutoRefresh;
                // Wait T_RFC for autorefresh to complete
                // The docs say it takes T_RFC for AutoRefresh to complete, but T_RP must be met
                // before issuing successive AutoRefresh commands. Because T_RFC>T_RP, assume
                // we just have to wait T_RFC.
                init_delayCounter <= Clocks(T_RFC, 2); // Delay T_RFC; -2 cycles getting to the next state
                init_state <= Init_State_Delay;
                init_nextState <= Init_State_Init+5;
            end
            
            Init_State_Init+5: begin
                // Set the operating mode of the SDRAM
                ramCmd <= RAM_Cmd_SetMode;
                // ram_ba: reserved
                ramBA <= 0;
                // ram_a:    write burst length,     test mode,  CAS latency,    burst type,     burst length
                ramA <= {    1'b0,                   2'b0,       3'b010,         1'b0,           3'b111};
                
                init_delayCounter <= Sub(C_MRD,2); // Delay C_MRD; -2 cycles getting to the next state
                init_state <= Init_State_Delay;
                init_nextState <= Init_State_Init+6;
            end
            
            Init_State_Init+6: begin
                // Set the extended operating mode of the SDRAM (applies only to Winbond RAMs)
                ramCmd <= RAM_Cmd_SetMode;
                // ram_ba: reserved
                ramBA <= 'b10;
                // ram_a:    output drive strength,      reserved,       self refresh banks
                ramA <= {    2'b0,                       2'b0,           3'b000};
                
                // TODO: make sure Sub(C_MRD,2) is the right number of cycles
                init_delayCounter <= Sub(C_MRD,2); // Delay C_MRD; -2 cycles getting to the next state
                init_state <= Init_State_Delay;
                init_nextState <= Init_State_Init+7;
            end
            
            Init_State_Init+7: begin
                init_done <= 1;
            end
            
            Init_State_Delay: begin
                if (!init_delayCounter) init_state <= init_nextState;
            end
            endcase
        
        end else begin
            // ====================
            // Cmd State Machine
            // ====================
            case (cmdState)
            Cmd_State_Idle: begin
                if (cmd_saved_ready && cmd_saved_trigger) begin
                    cmd_state <= Cmd_State_Handle;
                end else begin
                    // Keep accepting commands until we get one
                    cmd_ready <= 1;
                end
            end
            
            Cmd_State_Handle: begin
                
            end
            endcase
            
            // ====================
            // Data State Machine
            // ====================
            case (data_state)
            Data_State_Idle: begin
                if ()
            end
            
            Data_State_Write: begin
                // Activate the bank+row
                ramCmd <= RAM_Cmd_BankActivate;
                // TODO: fix with actual bank/row from the supplied block
                ramBA <= 0;
                ramA <= 0;
                
                data_delayCounter <= Data_BankActivateDelay;
                data_state <= Data_State_Delay;
                data_nextState <= Data_State_Write+1;
            end
            
            Data_State_Write+1: begin
                if (data_saved_ready && data_saved_trigger) begin
                    // TODO: fix with actual column address
                    ramA <= 0; // Supply the column address
                    ramDQOut <= data_saved_write; // Supply data to be written
                    ramDQOutEn <= 1;
                    ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                    ramCmd <= RAM_Cmd_Write; // Give write command
                    data_state <= Data_State_Write+2;
                
                // TODO: what if we don't accept new commands until the current block operation is complete? that should simplify our design...
                end else if (cmd_saved_trigger) begin
                    // There's a new command, so abort writing
                    // Wait the 'write recover' time before doing so.
                    // Datasheet (paraphrased):
                    // "The PrechargeAll command that interrupts a write burst should be
                    // issued ceil(tWR/tCK) cycles after the clock edge in which the
                    // last data-in element is registered."
                    data_delayCounter <= Clocks(T_WR,2); // -2 cycles getting to the next state
                    data_state <= Data_State_Delay;
                    data_nextState <= Data_State_WriteAbort;
                
                end else begin
                    data_ready <= 1; // Accept data
                end
            end
            
            Data_State_Write+2: begin
                // TODO: handle reaching the end of the block
                // TODO: handle crossing a bank/row boundary
                if (data_saved_ready && data_saved_trigger) begin
                    // Continue the write burst
                    ramA <= ramA+1; // Supply the column address
                    ramDQOut <= data_saved_write; // Supply data to be written
                    ramDQOutEn <= 1;
                    ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                    // Don't set `ramCmd` -- the burst continues with the NoOp command
                
                // TODO: what if we don't accept new commands until the current block operation is complete? that should simplify our design...
                end else if (cmd_saved_trigger) begin
                    // There's a new command, so abort writing
                    // Wait the 'write recover' time before doing so.
                    // Datasheet (paraphrased):
                    // "The PrechargeAll command that interrupts a write burst should be
                    // issued ceil(tWR/tCK) cycles after the clock edge in which the
                    // last data-in element is registered."
                    data_delayCounter <= Clocks(T_WR,2); // -2 cycles getting to the next state
                    data_state <= Data_State_Delay;
                    data_nextState <= Data_State_WriteAbort;
                
                end else begin
                    data_ready <= 1; // Accept data
                end
            end
            
            Data_State_WriteAbort: begin
                ramCmd <= RAM_Cmd_PrechargeAll;
                ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
                
                // After precharge completes, go idle
                data_delayCounter <= Clocks(T_RP,2); // -2 cycles getting to the next state
                data_state <= Data_State_Delay;
                data_nextState <= Data_State_Idle;
            end
            
            Data_State_Read: begin
            end
            
            Data_State_Refresh: begin
            end
            
            Data_State_Delay: begin
                if (!data_delayCounter) data_state <= data_nextState;
            end
            endcase
        end
    end
endmodule

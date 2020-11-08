`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

module RAMController #(
    parameter ClkFreq               = 24000000,
    parameter BlockSize             = 2304*1296,
    
    localparam WordWidth            = 16,
    localparam BankWidth            = 2,
    localparam RowWidth             = 13,
    localparam ColWidth             = 10,
    localparam DQMWidth             = 2,
    
    localparam AddrWidth            = BankWidth+RowWidth+ColWidth,
    localparam WordCount            = 64'b1<<AddrWidth,
    `define BankBits                AddrWidth-1                     -: BankWidth
    `define RowBits                 AddrWidth-BankWidth-1           -: RowWidth
    `define ColBits                 AddrWidth-BankWidth-RowWidth-1  -: ColWidth
    
    localparam BlockSizeCeilLog2    = $clog2(BlockSize),
    localparam BlockSizeCeilPow2    = 1<<BlockSizeCeilLog2,
    localparam BlockCount           = WordCount/BlockSizeCeilPow2,
    localparam BlockWidth           = $clog2(BlockCount)
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
    // initial begin
    //     $display("BlockSizeCeilLog2    = %0d", BlockSizeCeilLog2);
    //     $display("BlockSizeCeilPow2    = %0d", BlockSizeCeilPow2);
    //     $display("BlockCount           = %0d", BlockCount);
    //     $display("BlockWidth           = %0d", BlockWidth);
    //     $finish;
    // end
    
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
    
    function[AddrWidth-1:0] AddrFromBlock;
        input[BlockWidth-1:0] block;
        AddrFromBlock = block << BlockSizeCeilPow2;
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
    reg[WordWidth-1:0] ramDQOut = 0;
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
    
    localparam Init_State_Init              = 0; // +7
    localparam Init_State_Delay             = 8; // +0
    
    localparam Refresh_State_Idle           = 0; // +0
    localparam Refresh_State_Go             = 1; // +2
    localparam Refresh_State_Delay          = 4; // +0
    
    localparam Data_State_Idle              = 0; // +0
    localparam Data_State_Write             = 1; // +2
    localparam Data_State_WriteNextRow      = 4; // +0
    localparam Data_State_WriteAbort        = 5; // +0
    localparam Data_State_Read              = 6; // +0
    localparam Data_State_Delay             = 7; // +0
    
    reg init_done = 0;
    reg[3:0] init_state = 0;
    reg[3:0] init_nextState = 0;
    // TODO: verify that this is the correct math, since init_delayCounter is only used in the init states
    // At high clock speeds, Clocks(T_RFC,1) is the largest delay stored in delayCounter.
    // At low clock speeds, C_DQZ+1 is the largest delay stored in delayCounter.
    localparam Init_DelayCounterWidth = Max($clog2(Clocks(T_RFC,1)+1), $clog2(C_DQZ+1+1));
    reg[Init_DelayCounterWidth-1:0] init_delayCounter = 0;
    
    reg[3:0] refresh_state = 0;
    reg[3:0] refresh_nextState = 0;
    localparam Refresh_CounterWidth = $clog2(Clocks(T_REFI,1)+1);
    reg[Refresh_CounterWidth-1:0] refresh_counter = 0;
    localparam Refresh_DelayCounterWidth = Max($clog2(Clocks(T_RFC,1)+1), $clog2(C_DQZ+1+1));
    reg[Refresh_DelayCounterWidth-1:0] refresh_delayCounter = 0;
    reg refresh_pretrigger = 0;
    reg refresh_trigger = 0;
    
    localparam Refresh_StartDelay = Max(Max(Max(Max(Max(
        // T_RC: the previous cycle may have issued CmdBankActivate, so prevent violating T_RC
        // when we return to that command via StateHandleSaved after refreshing is complete.
        // -2 cycles getting to the next state
        Clocks(T_RC, 2),
        // T_RRD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RRD
        // when we return to that command via StateHandleSaved after refreshing is complete.
        // -2 cycles getting to the next state
        Clocks(T_RRD, 2)),
        // T_RAS: the previous cycle may have issued CmdBankActivate, so prevent violating T_RAS
        // since we're about to issue CmdPrechargeAll.
        // -2 cycles getting to the next state
        Clocks(T_RAS, 2)),
        // T_RCD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RCD
        // when we return to that command via StateHandleSaved after refreshing is complete.
        // -2 cycles getting to the next state
        Clocks(T_RCD, 2)),
        // T_RP: the previous cycle may have issued CmdPrechargeAll, so delay other commands
        // until precharging is complete.
        // -2 cycles getting to the next state
        Clocks(T_RP, 2)),
        // T_WR: the previous cycle may have issued CmdWrite, so delay other commands
        // until precharging is complete.
        // -2 cycles getting to the next state
        Clocks(T_WR, 2));
    
    reg[3:0] data_state = 0;
    reg[3:0] data_nextState = 0;
    reg[3:0] data_restartState = 0;
    reg[AddrWidth-1:0] data_blockAddr = 0;
    reg[$clog2(BlockSize)-1:0] data_blockCounter = 0;
    // TODO: verify that this is the correct math, since data_delayCounter is only used in the init states
    // At high clock speeds, Clocks(T_RFC,1) is the largest delay stored in delayCounter.
    // At low clock speeds, C_DQZ+1 is the largest delay stored in delayCounter.
    localparam Data_DelayCounterWidth = Max($clog2(Clocks(T_RFC,1)+1), $clog2(C_DQZ+1+1));
    reg[Data_DelayCounterWidth-1:0] data_delayCounter = 0;
    
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
        refresh_delayCounter <= refresh_delayCounter-1;
        // TODO: make sure `Clocks(T_REFI,2)` is right
        refresh_counter <= (refresh_counter ? refresh_counter-1 : Clocks(T_REFI,2));
        refresh_pretrigger <= !refresh_counter;
        if (refresh_pretrigger) refresh_trigger <= 1;
        
        cmd_ready <= 0; // Reset by default
        data_ready <= 0; // Reset by default
        
        // Reset RAM cmd state
        ramCmd <= RAM_Cmd_Nop;
        ramDQM <= RAM_DQM_Masked;
        ramDQOutEn <= 0;
        
        if (!init_done) begin
            case (init_state)
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
        
        end else if (refresh_trigger) begin
            case (refresh_state)
            Refresh_State_Idle: begin
                $display("[RAMController] Refresh triggered");
                // We don't know what state we came from, so wait the most conservative amount of time.
                refresh_delayCounter <= Refresh_StartDelay;
                refresh_state <= Refresh_State_Delay;
                refresh_nextState <= Refresh_State_Go;
            end
            
            Refresh_State_Go: begin
                // Precharge all banks
                ramCmd <= RAM_Cmd_PrechargeAll;
                ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
                
                // Wait T_RP (precharge to refresh/row activate) until we can issue CmdAutoRefresh
                refresh_delayCounter <= Clocks(T_RP,2); // -2 cycles getting to the next state
                refresh_state <= Refresh_State_Delay;
                refresh_nextState <= Refresh_State_Go+1;
            end
            
            Refresh_State_Go+1: begin
                // Issue auto-refresh command
                ramCmd <= RAM_Cmd_AutoRefresh;
                
                // Wait T_RFC (auto refresh time) to guarantee that the next command can
                // activate the same bank immediately
                //   -3 cycles getting to the next state: -2 to get to the next refresh state,
                //   then -1 to get to the next normal state after exiting refresh mode
                refresh_delayCounter <= Clocks(T_RFC,3);
                refresh_state <= Refresh_State_Delay;
                refresh_nextState <= Refresh_State_Go+2;
            end
            
            Refresh_State_Go+2: begin
                refresh_trigger <= 0;
                refresh_state <= Refresh_State_Idle;
                data_state <= data_restartState;
            end
            
            Refresh_State_Delay: begin
                if (!refresh_delayCounter) refresh_state <= refresh_nextState;
            end
            endcase
        
        end else begin
            // ====================
            // Data State Machine
            // ====================
            case (data_state)
            Data_State_Idle: begin
                if (cmd_ready && cmd_trigger) begin
                    data_blockAddr <= AddrFromBlock(cmd_block);
                    data_blockCounter <= BlockSize-1;
                    data_state <= (cmd_write ? Data_State_Write : Data_State_Read);
                    data_restartState <= (cmd_write ? Data_State_Write : Data_State_Read);
                end else begin
                    cmd_ready <= 1;
                end
            end
            
            Data_State_Write: begin
                // Activate the bank+row
                ramCmd <= RAM_Cmd_BankActivate;
                ramBA <= data_blockAddr[`BankBits];
                ramA <= data_blockAddr[`RowBits];
                
                data_delayCounter <= Data_BankActivateDelay;
                data_state <= Data_State_Delay;
                data_nextState <= Data_State_Write+1;
            end
            
            // TODO: we should merge Data_State_Write+1 and Data_State_Write+2. we need to because if a refresh interrupts the last write (data_blockCounter=0), we'll restart at Data_State_Write, which will run both Data_State_Write+1 and Data_State_Write+2, which will underflow data_blockCounter
            Data_State_Write+1: begin
                data_ready <= 1; // Accept more data
                if (data_ready && data_trigger) begin
                    $display("Wrote mem[%h] = %h", data_blockAddr, data_write);
                    ramA <= data_blockAddr[`ColBits]; // Supply the column address
                    ramDQOut <= data_write; // Supply data to be written
                    ramDQOutEn <= 1;
                    ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                    ramCmd <= RAM_Cmd_Write; // Give write command
                    data_blockAddr <= data_blockAddr+1;
                    data_blockCounter <= data_blockCounter-1;
                    data_state <= Data_State_Write+2;
                end
            end
            
            Data_State_Write+2: begin
                data_ready <= 1; // Accept more data
                if (data_ready && data_trigger) begin
                    // Continue the write burst
                    $display("Wrote mem[%h] = %h", data_blockAddr, data_write);
                    ramA <= data_blockAddr[`ColBits]; // Supply the column address
                    ramDQOut <= data_write; // Supply data to be written
                    ramDQOutEn <= 1;
                    ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                    data_blockAddr <= data_blockAddr+1;
                    data_blockCounter <= data_blockCounter-1;
                    // Don't set `ramCmd` -- the burst continues with the NoOp command
                    
                    // Handle reaching the end of a row
                    if (&data_blockAddr[`RowBits]) begin
                        $display("Crossed row boundary");
                        // Override `data_ready=1` above since we can't handle new data in the next state
                        data_ready <= 0;
                        
                        // Abort writing
                        // Wait the 'write recover' time before doing so.
                        // Datasheet (paraphrased):
                        //   "The PrechargeAll command that interrupts a write burst should be
                        //   issued ceil(tWR/tCK) cycles after the clock edge in which the
                        //   last data-in element is registered."
                        data_delayCounter <= Clocks(T_WR,2); // -2 cycles getting to the next state
                        data_state <= Data_State_Delay;
                        data_nextState <= Data_State_WriteNextRow;
                    
                    // Handle reaching the end of the block
                    end else if (!data_blockCounter) begin
                        $display("End of block");
                        // Override `data_ready=1` above since we're done with the block
                        data_ready <= 0;
                        
                        // Abort writing
                        // Wait the 'write recover' time before doing so.
                        // Datasheet (paraphrased):
                        //   "The PrechargeAll command that interrupts a write burst should be
                        //   issued ceil(tWR/tCK) cycles after the clock edge in which the
                        //   last data-in element is registered."
                        data_delayCounter <= Clocks(T_WR,2); // -2 cycles getting to the next state
                        data_state <= Data_State_Delay;
                        data_nextState <= Data_State_WriteAbort;
                        // After this point, if refresh mode interrupts us, return to the Idle state since we're done
                        data_restartState <= Data_State_Idle;
                    end
                
                end else begin
                    // The data flow was interrupted, so we need to re-issue the
                    // write command when the flow starts again.
                    data_state <= Data_State_Write+1;
                end
            end
            
            // TODO: try merging Data_State_WriteNextRow + Data_State_WriteAbort
            Data_State_WriteNextRow: begin
                ramCmd <= RAM_Cmd_PrechargeAll;
                ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
                
                // After precharge completes, continue writing
                data_delayCounter <= Clocks(T_RP,2); // -2 cycles getting to the next state
                data_state <= Data_State_Delay;
                data_nextState <= Data_State_Write;
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
            
            Data_State_Delay: begin
                if (!data_delayCounter) data_state <= data_nextState;
            end
            endcase
            
            // Override our `_ready` flags if we're refreshing on the next cycle
            if (refresh_pretrigger) begin
                cmd_ready <= 0;
                data_ready <= 0;
            end
        end
    end
endmodule

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

module RAMController #(
    parameter ClkFreq               = 24000000,
    parameter RAMClkDelay           = 0,
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
    input wire[WordWidth-1:0]   data_write,     // Data to write to RAM
    output wire[WordWidth-1:0]  data_read,      // Data read from RAM
    
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
    localparam T_INIT                   = 200000;   // Power up initialization time
    localparam T_REFI                   = 7812;     // Time between refreshes
    localparam T_RC                     = 68;       // Bank activate to bank activate time (same bank)
    localparam T_RFC                    = 72;       // Refresh time
    localparam T_RRD                    = 15;       // Row activate to row activate time (different banks)
    localparam T_RAS                    = 45;       // Row activate to precharge time (same bank)
    localparam T_RCD                    = 18;       // Bank activate to read/write time (same bank)
    localparam T_RP                     = 18;       // Precharge to refresh/row activate (same bank)
    localparam T_WR                     = 15;       // Write recover time
    
    // Timing parameters (clock cycles)
    localparam C_CAS                    = 2;        // Column address strobe (CAS) delay
    localparam C_MRD                    = 2;        // (T_MRD) set mode command to bank activate/refresh command delay
    
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
    
    function[AddrWidth-1:0] AddrFromBlock;
        input[BlockWidth-1:0] block;
        AddrFromBlock = block << BlockSizeCeilLog2;
    endfunction
    
    // ====================
    // ram_clk
    // ====================
    Delay #(
        .Count(RAMClkDelay)
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
    assign data_read = ramDQIn;
    
    localparam Data_State_Init              = 0;    // +6
    localparam Data_State_Idle              = 7;    // +0
    localparam Data_State_WriteStart        = 8;    // +0
    localparam Data_State_Write             = 9;    // +0
    localparam Data_State_ReadStart         = 10;   // +0
    localparam Data_State_Read              = 11;   // +5
    localparam Data_State_Finish            = 17;   // +0
    localparam Data_State_Refresh           = 18;   // +2
    localparam Data_State_Count             = 21;
    
    reg init_done = 0;
    localparam Init_Delay = Clocks(T_INIT,1); // -1 cycle getting to the next state
    
    localparam Refresh_Delay = Clocks(T_REFI,2); // -2 cycles:
                                                 //   -1: Because waiting N cycles requires loading a counter with N-1.
                                                 //   -1: Because Clocks() ceils the result, so if we need to
                                                 //       wait 10.5 cycles, Clocks() will return 11, when we
                                                 //       actually want 10. This can cause us to be more
                                                 //       conservative than necessary in the case where refresh period
                                                 //       is an exact multiple of the clock period, but refreshing
                                                 //       one cycle earlier is fine.
    localparam Refresh_CounterWidth = `RegWidth(Refresh_Delay);
    reg[Refresh_CounterWidth-1:0] refresh_counter = 0;
    localparam Refresh_StartDelay = `Max6(
        // T_RC: the previous cycle may have issued CmdBankActivate, so prevent violating T_RC
        // when we return to that command via StateHandleSaved after refreshing is complete.
        // -1 cycle getting to the next state
        Clocks(T_RC,1),
        // T_RRD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RRD
        // when we return to that command via StateHandleSaved after refreshing is complete.
        // -1 cycle getting to the next state
        Clocks(T_RRD,1),
        // T_RAS: the previous cycle may have issued CmdBankActivate, so prevent violating T_RAS
        // since we're about to issue CmdPrechargeAll.
        // -1 cycle getting to the next state
        Clocks(T_RAS,1),
        // T_RCD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RCD
        // when we return to that command via StateHandleSaved after refreshing is complete.
        // -1 cycle getting to the next state
        Clocks(T_RCD,1),
        // T_RP: the previous cycle may have issued CmdPrechargeAll, so delay other commands
        // until precharging is complete.
        // -1 cycle getting to the next state
        Clocks(T_RP,1),
        // T_WR: the previous cycle may have issued CmdWrite, so delay other commands
        // until precharging is complete.
        // -1 cycle getting to the next state
        Clocks(T_WR,1)
    );
    
    reg[Data_State_Count-1:0] data_state = 0;
    reg data_modeRead = 0;
    reg data_modeWrite = 0;
    reg[4:0] data_nextState = 0;
    reg[AddrWidth-1:0] data_addr = 0;
    reg[BlockSizeCeilLog2-1:0] data_counter = 0;
    
    localparam Data_BankActivateDelay = `Max4(
        // T_RCD: ensure "bank activate to read/write time".
        // -1 cycle getting to the next state
        Clocks(T_RCD,1),
        // T_RAS: ensure "row activate to precharge time", ie that we don't
        // CmdPrechargeAll too soon after we activate the bank.
        // -1 cycle getting to the next state
        Clocks(T_RAS,1),
        // T_RC: ensure "activate bank A to activate bank A time", to ensure that the next
        // bank can't be activated too soon after this bank activation.
        // -1 cycle getting to the next state
        Clocks(T_RC,1),
        // T_RRD: ensure "activate bank A to activate bank B time", to ensure that the next
        // bank can't be activated too soon after this bank activation.
        // -1 cycle getting to the next state
        Clocks(T_RRD,1)
    );
    localparam Data_DelayCounterWidth = `RegWidth12(
        // Init states
        Init_Delay,
        10,
        Clocks(T_RP,1),
        Clocks(T_RFC,1),
        `Sub(C_MRD,1),
        
        Data_BankActivateDelay,
        Clocks(T_WR,1),
        C_CAS+1,
        Clocks(T_RP,1),
        
        // Refresh states
        Refresh_StartDelay,
        Clocks(T_RP,1),
        Clocks(T_RFC,1)
    );
    reg[Data_DelayCounterWidth-1:0] data_delayCounter = 0;
    
    reg data_write_issueCmd = 0;
    reg data_stateInit = 0;
    
	always @(posedge clk) begin
        if (data_delayCounter) begin
            data_delayCounter <= data_delayCounter-1;
        end else begin
            data_state <= data_state<<1|!data_stateInit;
            data_stateInit <= 1;
        end
        refresh_counter <= (refresh_counter ? refresh_counter-1 : Refresh_Delay);
        // refresh_counter <= 2;
        
        cmd_ready <= 0; // Reset by default
        data_ready <= 0; // Reset by default
        
        // Reset RAM cmd state
        ramCmd <= RAM_Cmd_Nop;
        ramDQM <= RAM_DQM_Masked;
        ramDQOutEn <= 0;
        
        // ====================
        // Data State Machine
        // ====================
        if (!data_delayCounter) begin
            if (data_state[Data_State_Init]) begin
                // Initialize registers
                ramCKE <= 0;
                data_delayCounter <= Init_Delay;
            end
        
            if (data_state[Data_State_Init+1]) begin
                $display("Data_State_Init+1");
                // Bring ram_cke high for a bit before issuing commands
                ramCKE <= 1;
                data_delayCounter <= 10; // Delay 10 cycles
            end
        
            if (data_state[Data_State_Init+2]) begin
                $display("Data_State_Init+2");
                // Precharge all banks
                ramCmd <= RAM_Cmd_PrechargeAll;
                ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
            
                data_delayCounter <= Clocks(T_RP,1); // -1 cycle getting to the next state
            end
        
            if (data_state[Data_State_Init+3]) begin
                // Autorefresh 1/2
                ramCmd <= RAM_Cmd_AutoRefresh;
                // Wait T_RFC for autorefresh to complete
                // The docs say it takes T_RFC for AutoRefresh to complete, but T_RP must be met
                // before issuing successive AutoRefresh commands. Because T_RFC>T_RP, assume
                // we just have to wait T_RFC.
                data_delayCounter <= Clocks(T_RFC,1); // -1 cycle getting to the next state
            end
        
            if (data_state[Data_State_Init+4]) begin
                // Autorefresh 2/2
                ramCmd <= RAM_Cmd_AutoRefresh;
                // Wait T_RFC for autorefresh to complete
                // The docs say it takes T_RFC for AutoRefresh to complete, but T_RP must be met
                // before issuing successive AutoRefresh commands. Because T_RFC>T_RP, assume
                // we just have to wait T_RFC.
                data_delayCounter <= Clocks(T_RFC,1); // -1 cycle getting to the next state
            end
        
            if (data_state[Data_State_Init+5]) begin
                // Set the operating mode of the SDRAM
                ramCmd <= RAM_Cmd_SetMode;
                // ram_ba: reserved
                ramBA <= 0;
                // ram_a:    write burst length,     test mode,  CAS latency,    burst type,     burst length
                ramA <= {    1'b0,                   2'b0,       3'b010,         1'b0,           3'b111};
            
                data_delayCounter <= `Sub(C_MRD,1); // -1 cycle getting to the next state
            end
        
            if (data_state[Data_State_Init+6]) begin
                // Set the extended operating mode of the SDRAM (applies only to Winbond RAMs)
                ramCmd <= RAM_Cmd_SetMode;
                // ram_ba: reserved
                ramBA <= 'b10;
                // ram_a:    output drive strength,      reserved,       self refresh banks
                ramA <= {    2'b0,                       2'b0,           3'b000};
            
                init_done <= 1;
            
                data_delayCounter <= `Sub(C_MRD,1); // -1 cycle getting to the next state
            end
        
            if (data_state[Data_State_Idle]) begin
                data_state[Data_State_Idle+1] <= 0;
                
                if (cmd_ready && cmd_trigger) begin
                    data_addr <= AddrFromBlock(cmd_block);
                    data_counter <= BlockSize-1;
                    data_modeWrite <= cmd_write;
                    data_state[Data_State_WriteStart] <= cmd_write;
                    
                    data_modeRead <= !cmd_write;
                    data_state[Data_State_ReadStart] <= !cmd_write;
                end else begin
                    // $display("[RAM-CTRL] IDLE");
                    cmd_ready <= 1;
                    // Stay in current state
                    data_state[Data_State_Idle]   <= 1;
                end
            end
        
            if (data_state[Data_State_WriteStart]) begin
                // $display("[RAM-CTRL] Data_State_Start");
                // Activate the bank+row
                ramCmd <= RAM_Cmd_BankActivate;
                ramBA <= data_addr[`BankBits];
                ramA <= data_addr[`RowBits];
            
                data_write_issueCmd <= 1; // The first write needs to issue the write command
                data_delayCounter <= Data_BankActivateDelay;
            end
        
            if (data_state[Data_State_Write]) begin
                data_state[Data_State_Write+1] <= 0;
                
                // $display("[RAM-CTRL] Data_State_Write");
                data_ready <= 1; // Accept more data
                if (data_ready && data_trigger) begin
                    // $display("[RAM-CTRL] Wrote mem[%h] = %h", data_addr, data_write);
                    if (data_write_issueCmd) ramA <= data_addr[`ColBits]; // Supply the column address
                    ramDQOut <= data_write; // Supply data to be written
                    ramDQOutEn <= 1;
                    ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                    if (data_write_issueCmd) ramCmd <= RAM_Cmd_Write; // Give write command
                    data_addr <= data_addr+1;
                    data_counter <= data_counter-1;
                    data_write_issueCmd <= 0; // Reset after we issue the write command
                
                    if (!data_counter) begin
                        // Clear data_modeWrite because we're done
                        data_modeWrite <= 0;
                    end
                
                    // Handle reaching the end of a row or the end of block
                    if (&data_addr[`ColBits] || !data_counter) begin
                        // $display("[RAM-CTRL] End of row / end of block");
                        // Override `data_ready=1` above since we can't handle new data in the next state
                        data_ready <= 0;
                    
                        // Abort writing
                        // Wait the 'write recover' time before doing so.
                        // Datasheet (paraphrased):
                        //   "The PrechargeAll command that interrupts a write burst should be
                        //   issued ceil(tWR/tCK) cycles after the clock edge in which the
                        //   last data-in element is registered."
                        data_delayCounter <= Clocks(T_WR,1); // -1 cycles getting to Data_State_Finish
                        data_state[Data_State_Finish] <= 1;
                    
                    end else begin
                        // Stay in current state
                        data_state[Data_State_Write] <= 1;
                    end
            
                end else begin
                    // $display("[RAM-CTRL] Restart write");
                    // The data flow was interrupted, so we need to re-issue the
                    // write command when the flow starts again.
                    data_write_issueCmd <= 1;
                    // Stay in current state
                    data_state[Data_State_Write] <= 1;
                end
            end
        
            if (data_state[Data_State_ReadStart]) begin
                // $display("[RAM-CTRL] Data_State_Start");
                // Activate the bank+row
                ramCmd <= RAM_Cmd_BankActivate;
                ramBA <= data_addr[`BankBits];
                ramA <= data_addr[`RowBits];
            
                data_delayCounter <= Data_BankActivateDelay;
            end
        
            if (data_state[Data_State_Read]) begin
                // $display("[RAM-CTRL] Data_State_Read");
                // $display("[RAM-CTRL] Read mem[%h] = %h", data_addr, data_write);
                ramA <= data_addr[`ColBits]; // Supply the column address
                ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                ramCmd <= RAM_Cmd_Read; // Give read command
            end
            
            if (data_state[Data_State_Read+1]) begin
                // $display("[RAM-CTRL] Data_State_Read+1");
                ramDQM <= RAM_DQM_Unmasked; // Unmask the data
            end
            
            if (data_state[Data_State_Read+2]) begin
                // $display("[RAM-CTRL] Data_State_Read+1");
                ramDQM <= RAM_DQM_Unmasked; // Unmask the data
            end
            
            if (data_state[Data_State_Read+3]) begin
                // $display("[RAM-CTRL] Data_State_Read+1");
                ramDQM <= RAM_DQM_Unmasked; // Unmask the data
            end
            
            if (data_state[Data_State_Read+4]) begin
                // $display("[RAM-CTRL] Data_State_Read+1");
                ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                data_ready <= 1; // Notify that data is available
            end
            
            if (data_state[Data_State_Read+5]) begin
                data_state[Data_State_Read+5+1] <= 0;
                
                // if (data_ready) $display("[RAM-CTRL] Read mem[%h] = %h", data_addr, data_read);
                if (data_trigger) begin
                    // $display("[RAM-CTRL] Read mem[%h] = %h", data_addr, data_read);
                    ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                    data_addr <= data_addr+1;
                    data_counter <= data_counter-1;
                
                    if (!data_counter) begin
                        // Clear data_modeRead because we're done
                        data_modeRead <= 0;
                    end
                
                    // Handle reaching the end of a row or the end of block
                    if (&data_addr[`ColBits] || !data_counter) begin
                        // $display("[RAM-CTRL] End of row / end of block");
                        // Abort reading
                        data_state[Data_State_Finish] <= 1;
                    end else begin
                        // Notify that more data is available
                        data_ready <= 1;
                        // Stay in current state
                        data_state[Data_State_Read+5] <= 1;
                    end
            
                end else begin
                    // $display("[RAM-CTRL] Restart read");
                    // If the current data wasn't accepted, we need restart reading
                    data_state[Data_State_Read] <= 1;
                end
            end
        
            if (data_state[Data_State_Finish]) begin
                data_state[Data_State_Finish+1] <= 0;
                
                // $display("[RAM-CTRL] Data_State_Finish");
                ramCmd <= RAM_Cmd_PrechargeAll;
                ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
            
                // After precharge completes, continue writing if there's more data
                data_delayCounter <= Clocks(T_RP,1); // -1 cycle getting to the next state
                
                data_state[Data_State_Idle]         <= !data_modeRead && !data_modeWrite;
                data_state[Data_State_ReadStart]    <= data_modeRead;
                data_state[Data_State_WriteStart]   <= data_modeWrite;
            end
            
            if (data_state[Data_State_Refresh]) begin
                // $display("[RAM-CTRL] Refresh start");
                // We don't know what state we came from, so wait the most conservative amount of time.
                data_delayCounter <= Refresh_StartDelay;
            end
            
            if (data_state[Data_State_Refresh+1]) begin
                // Precharge all banks
                ramCmd <= RAM_Cmd_PrechargeAll;
                ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll

                // Wait T_RP (precharge to refresh/row activate) until we can issue CmdAutoRefresh
                data_delayCounter <= Clocks(T_RP,1); // -1 cycle getting to the next state
            end

            if (data_state[Data_State_Refresh+2]) begin
                $display("Refresh time: %0d", $time);
                
                data_state[Data_State_Refresh+2+1] <= 0;
                // Issue auto-refresh command
                ramCmd <= RAM_Cmd_AutoRefresh;
                // Wait T_RFC (auto refresh time) to guarantee that the next command can
                // activate the same bank immediately
                data_delayCounter <= Clocks(T_RFC,1); // -1 cycle getting to the next state:
                
                data_state[Data_State_Idle]         <= !data_modeRead && !data_modeWrite;
                data_state[Data_State_ReadStart]    <= data_modeRead;
                data_state[Data_State_WriteStart]   <= data_modeWrite;
                
                $display("[RAM-CTRL] Refresh done");
            end
        end
        
        if (init_done && !refresh_counter) begin
            // Override our `_ready` flags if we're refreshing on the next cycle
            cmd_ready <= 0;
            data_ready <= 0;

            data_state <= 0;
            data_state[Data_State_Refresh] <= 1;
            data_delayCounter <= 0;
        end
    end
endmodule

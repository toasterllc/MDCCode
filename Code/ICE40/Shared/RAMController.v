`ifndef RAMController_v
`define RAMController_v

`include "Util.v"
`include "Delay.v"

`define RAMController_Cmd_None      2'b00
`define RAMController_Cmd_Write     2'b01
`define RAMController_Cmd_Read      2'b10
`define RAMController_Cmd_Stop      2'b11

module RAMController #(
    parameter ClkFreq                   = 16_000_000,
    parameter RAMClkDelay               = 0,
    parameter BlockCount                = 16,   // Number of blocks to divide the RAM into
    
    localparam WordWidth                = 16,
    localparam BankWidth                = 2,
    localparam RowWidth                 = 12,
    localparam ColWidth                 = 9,
    localparam DQMWidth                 = 2,
    
    localparam AddrWidth                = BankWidth+RowWidth+ColWidth,
    localparam WordCount                = 64'b1<<AddrWidth,
    `define BankBits                    AddrWidth-1                     -: BankWidth
    `define RowBits                     AddrWidth-BankWidth-1           -: RowWidth
    `define ColBits                     AddrWidth-BankWidth-RowWidth-1  -: ColWidth
    
    localparam BlockWordCount           = WordCount/BlockCount,
    localparam BlockWordCountRegWidth   = `RegWidth(BlockWordCount-1),
    localparam BlockCountRegWidth       = `RegWidth(BlockCount-1)
)(
    input wire                  clk,            // Clock
    
    // TODO: consider re-ordering: cmd_block, cmd_write, cmd_trigger
    // Command port (clock domain: `clk`)
    input wire[1:0]             cmd,                // CmdWrite/CmdRead/CmdStop
    input wire[BlockCountRegWidth-1:0]
                                cmd_block,          // Block index
    
    // TODO: consider re-ordering: write_data, write_trigger, write_ready
    // Write port (clock domain: `clk`)
    output reg                  write_ready = 0,    // `write_data` accepted
    input wire                  write_trigger,      // Only effective if `write_ready`=1
    input wire[WordWidth-1:0]   write_data,         // Data to write to RAM
    
    // TODO: consider re-ordering: read_data, read_trigger, read_ready
    // Read port (clock domain: `clk`)
    output reg                  read_ready = 0,     // `read_data` valid
    input wire                  read_trigger,       // Only effective if `read_ready`=1
    output wire[WordWidth-1:0]  read_data,          // Data read from RAM
    
    // RAM port (clock domain: `ram_clk`)
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
    // Alliance AS4C8M16MSA-6BIN Timing parameters (nanoseconds)
    localparam T_INIT                   = 200000;   // Power up initialization time
    localparam T_REFI                   = 15625;    // Time between refreshes (4K refreshes / 64ms)
    localparam T_RC                     = 60;       // Bank activate to bank activate time (same bank)
    localparam T_RFC                    = 80;       // Refresh time
    localparam T_RRD                    = 12;       // Row activate to row activate time (different banks)
    localparam T_RAS                    = 48;       // Row activate to precharge time (same bank)
    localparam T_RCD                    = 18;       // Bank activate to read/write time (same bank)
    localparam T_RP                     = 18;       // Precharge to refresh/row activate (same bank)
    localparam T_WR                     = 15;       // Write recover time
    
    // Timing parameters (clock cycles)
    // C_CAS: Column address strobe (CAS) delay cycles
    //   CAS=2 => Fmax=83 MHz
    //   CAS=3 => Fmax=166 MHz
    localparam C_CAS                    = 3;
    // C_MRD (T_MRD): Set mode -> bank activate/refresh delay cycles
    localparam C_MRD                    = 2;
    
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
    
    function[AddrWidth-1:0] AddrFromBlock;
        input[BlockCountRegWidth-1:0] block;
        AddrFromBlock = block << BlockWordCountRegWidth;
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
    assign read_data = ramDQIn;
    
//     // TODO: we need to remove this when testing the RAM with the SDRAM chip sim (mt48h32m16lf)
// `ifdef SIM
//     assign ramDQIn = 16'hABCD;
// `endif
    
    // ====================
    // Init State Machine Registers
    // ====================
    localparam Init_State_Init              = 0;    // +7
    localparam Init_State_Nop               = 8;    // +0
    localparam Init_State_Delay             = 9;    // +0
    localparam Init_State_Count             = 10;
    localparam Init_State_Width             = `RegWidth(Init_State_Count-1);
    
    reg[Init_State_Width-1:0] init_state = 0;
    reg[Init_State_Width-1:0] init_nextState = 0;
    
    localparam Init_Delay = Clocks(ClkFreq,T_INIT,2); // -2 cycles getting to the next state
    localparam Init_DelayCounterWidth = `RegWidth5(
        // Init states
        Init_Delay,
        10,
        Clocks(ClkFreq,T_RP,2),
        Clocks(ClkFreq,T_RFC,2),
        `Sub(C_MRD,2)
    );
    reg[Init_DelayCounterWidth-1:0] init_delayCounter = 0;
    reg init_done = 0;
    
    
    
    
    
    
    
    // ====================
    // Refresh State Machine Registers
    // ====================
    localparam Refresh_State_Go     = 0;    // +3
    localparam Refresh_State_Delay  = 4;    // +1
    localparam Refresh_State_Count  = 6;
    localparam Refresh_State_Width  = `RegWidth(Refresh_State_Count-1);
    // Refresh_Delay: -2 cycles because:
    //   -1: Because waiting N cycles requires loading a counter with N-1.
    //   -1: Because Clocks(ClkFreq,) ceils the result, so if we need to
    //       wait 10.5 cycles, Clocks(ClkFreq,) will return 11, when we
    //       actually want 10. This can cause us to be more
    //       conservative than necessary in the case where refresh period
    //       is an exact multiple of the clock period, but refreshing
    //       one cycle earlier is fine.
    localparam Refresh_Delay = Clocks(ClkFreq,T_REFI,2);
    reg[`RegWidth(Refresh_Delay)-1:0] refresh_counter = 0;
    localparam Refresh_DelayCounterWidth = `RegWidth3(
        InterruptDelay,
        Clocks(ClkFreq,T_RP,2),
        Clocks(ClkFreq,T_RFC,2)
    );
    reg[Refresh_DelayCounterWidth-1:0] refresh_delayCounter = 0;
    reg[Refresh_State_Width-1:0] refresh_state = 0;
    reg[Refresh_State_Width-1:0] refresh_nextState = 0;
    reg refresh_trigger = 0;
    
    
    
    localparam InterruptDelay = `Max6(
        // T_RC: the previous cycle may have issued RAM_Cmd_BankActivate, so prevent violating T_RC
        // when we finish refreshing.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RC,2),
        // T_RRD: the previous cycle may have issued RAM_Cmd_BankActivate, so prevent violating T_RRD
        // when we finish refreshing.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RRD,2),
        // T_RAS: the previous cycle may have issued RAM_Cmd_BankActivate, so prevent violating T_RAS
        // since we're about to issue CmdPrechargeAll.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RAS,2),
        // T_RCD: the previous cycle may have issued RAM_Cmd_BankActivate, so prevent violating T_RCD
        // when we finish refreshing.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RCD,2),
        // T_RP: the previous cycle may have issued RAM_Cmd_PrechargeAll, so delay other commands
        // until precharging is complete.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RP,2),
        // T_WR: the previous cycle may have issued RAM_Cmd_Write, so delay other commands
        // until precharging is complete.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_WR,2)
    );
    
    
    
    // ====================
    // Data State Machine Registers
    // ====================
    localparam Data_State_Idle              = 0;    // +0
    localparam Data_State_WriteStart        = 1;    // +0
    localparam Data_State_Write             = 2;    // +1
    localparam Data_State_ReadStart         = 4;    // +0
    localparam Data_State_Read              = 5;    // +2
    localparam Data_State_Finish            = 8;    // +0
    localparam Data_State_Delay             = 9;    // +0
    localparam Data_State_Count             = 10;
    localparam Data_State_Width             = `RegWidth(Data_State_Count-1);
    
    reg[Data_State_Width-1:0] data_state = 0;
    reg[Data_State_Width-1:0] data_nextState = 0;
    reg[Data_State_Width-1:0] data_restartState = 0;
    
    reg[AddrWidth-1:0] data_addr = 0;
    
    localparam Data_BankActivateDelay = (
        // T_RCD: ensure "bank activate to read/write time".
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RCD,2)
    );
    
    localparam Data_FinishDelay = `Max4(
        // T_WR: ensure "write recover" time before precharging after a write
        // Datasheet (paraphrased):
        //   "The PrechargeAll command that interrupts a write burst should be
        //   issued ceil(tWR/tCK) cycles after the clock edge in which the
        //   last data-in element is registered."
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_WR,2),
        // T_RAS: ensure "row activate to precharge time", ie that we don't
        // CmdPrechargeAll too soon after we activate the bank.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RAS,2),
        // T_RC: ensure "activate bank A to activate bank A time", to ensure that the next
        // bank can't be activated too soon after this bank activation.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RC,2),
        // T_RRD: ensure "activate bank A to activate bank B time", to ensure that the next
        // bank can't be activated too soon after this bank activation.
        // -2 cycles getting to the next state
        Clocks(ClkFreq,T_RRD,2)
    );
    
    localparam Data_DelayCounterWidth = `RegWidth6(
        Data_BankActivateDelay,
        Data_FinishDelay,
        Clocks(ClkFreq,T_WR,2),
        C_CAS+1,
        Clocks(ClkFreq,T_RP,2),
        InterruptDelay
    );
    reg[Data_DelayCounterWidth-1:0] data_delayCounter = 0;
    
    reg data_write_issueCmd = 0;
    
	always @(posedge clk) begin
        init_delayCounter <= init_delayCounter-1;
        refresh_delayCounter <= refresh_delayCounter-1;
        data_delayCounter <= data_delayCounter-1;
        refresh_counter <= (refresh_counter ? refresh_counter-1 : Refresh_Delay);
        // data_refreshCounter <= 2;
        
        // Reset by default
        write_ready <= 0;
        read_ready <= 0;
        
        // Reset RAM cmd state
        ramCmd <= RAM_Cmd_Nop;
        ramDQM <= RAM_DQM_Masked;
        ramDQOutEn <= 0;
        
        // ====================
        // Init State Machine
        // ====================
        case (init_state)
        Init_State_Init: begin
            // Initialize registers
            ramCKE <= 0;
            init_delayCounter <= Init_Delay;
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
            
            init_delayCounter <= Clocks(ClkFreq,T_RP,2); // -2 cycles getting to the next state
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
            init_delayCounter <= Clocks(ClkFreq,T_RFC,2); // -2 cycles getting to the next state
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
            init_delayCounter <= Clocks(ClkFreq,T_RFC,2); // Delay T_RFC; -2 cycles getting to the next state
            init_state <= Init_State_Delay;
            init_nextState <= Init_State_Init+5;
        end
        
        Init_State_Init+5: begin
            // Set the operating mode of the SDRAM
            ramCmd <= RAM_Cmd_SetMode;
            // ram_ba: reserved
            ramBA <= 0;
            // ram_a
            ramA <= {
                2'b0,       // reserved
                1'b0,       // write burst length: controlled by `burst length` field
                2'b0,       // operational mode: standard
                C_CAS[2:0], // CAS latency: C_CAS
                1'b0,       // burst type: sequential
                3'b111      // burst length: full page
            };
            
            init_delayCounter <= `Sub(C_MRD,2); // -2 cycles getting to the next state
            init_state <= Init_State_Delay;
            init_nextState <= Init_State_Init+6;
        end
        
        Init_State_Init+6: begin
            // Set the extended operating mode of the SDRAM
            ramCmd <= RAM_Cmd_SetMode;
            // ram_ba: reserved
            ramBA <= 'b10;
            // ram_a
            ramA <= {
                4'b0,   // reserved
                3'b0,   // output drive strength: 100%
                2'b0,   // reserved
                3'b000  // partial array self refresh: all banks
            };
            
            init_delayCounter <= `Sub(C_MRD,2); // -2 cycles getting to the next state
            init_state <= Init_State_Delay;
            init_nextState <= Init_State_Init+7;
        end
        
        Init_State_Init+7: begin
            init_done <= 1;
            init_state <= Init_State_Nop;
        end
        
        Init_State_Nop: begin
        end
        
        Init_State_Delay: begin
            if (!init_delayCounter) init_state <= init_nextState;
        end
        endcase
        
        if (init_done) begin
            if (refresh_trigger) begin
                // ====================
                // Refresh State Machine
                // ====================
                case (refresh_state)
                Refresh_State_Go: begin
                    // $display("[RAM-CTRL] Refresh start");
                    // We don't know what state we came from, so wait the most conservative amount of time.
                    refresh_delayCounter <= InterruptDelay;
                    refresh_state <= Refresh_State_Delay;
                    refresh_nextState <= Refresh_State_Go+1;
                end
                
                Refresh_State_Go+1: begin
                    // Precharge all banks
                    ramCmd <= RAM_Cmd_PrechargeAll;
                    ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
                    
                    refresh_delayCounter <= Clocks(ClkFreq,T_RP,2); // -2 cycles getting to the next state
                    refresh_state <= Refresh_State_Delay;
                    refresh_nextState <= Refresh_State_Go+2;
                end
                
                Refresh_State_Go+2: begin
                    // $display("[RAM-CTRL] Refresh (time: %0d)", $time);
                    // Issue auto-refresh command
                    ramCmd <= RAM_Cmd_AutoRefresh;
                    // Wait T_RFC (auto refresh time) to guarantee that the next command can
                    // activate the same bank immediately
                    refresh_delayCounter <= Clocks(ClkFreq,T_RFC,3); // -2 cycles getting to the next state
                    refresh_state <= Refresh_State_Delay;
                    refresh_nextState <= Refresh_State_Go+3;
                end
                
                Refresh_State_Go+3: begin
                    refresh_state <= Refresh_State_Go;
                    refresh_trigger <= 0;
                    // Return to whatever state was underway
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
                end
                
                Data_State_WriteStart: begin
                    // $display("[RAM-CTRL] Data_State_Start");
                    // Activate the bank+row
                    ramCmd <= RAM_Cmd_BankActivate;
                    ramBA <= data_addr[`BankBits];
                    ramA <= data_addr[`RowBits];
                    
                    data_write_issueCmd <= 1; // The first write needs to issue the write command
                    data_delayCounter <= Data_BankActivateDelay;
                    data_state <= Data_State_Delay;
                    data_nextState <= Data_State_Write;
                end
                
                Data_State_Write: begin
                    write_ready <= 1;
                    data_state <= Data_State_Write+1;
                end
                
                Data_State_Write+1: begin
                    // $display("[RAM-CTRL] Data_State_Write");
                    write_ready <= 1; // Accept more data
                    if (write_trigger) begin
                        // $display("[RAM-CTRL] Wrote mem[%h] = %h", data_addr, write_data);
                        if (data_write_issueCmd) ramA <= data_addr[`ColBits]; // Supply the column address
                        ramDQOut <= write_data; // Supply data to be written
                        ramDQOutEn <= 1;
                        ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                        if (data_write_issueCmd) ramCmd <= RAM_Cmd_Write; // Give write command
                        data_addr <= data_addr+1;
                        data_write_issueCmd <= 0; // Reset after we issue the write command
                        
                        // Handle reaching the end of a row or the end of block
                        if (&data_addr[`ColBits]) begin
                            // $display("[RAM-CTRL] End of row / end of block");
                            // Override `write_ready=1` above since we can't handle new data in the next state
                            write_ready <= 0;
                            
                            // Abort writing
                            data_delayCounter <= Data_FinishDelay;
                            data_state <= Data_State_Delay;
                            data_nextState <= Data_State_Finish;
                        end
                        
                    end else begin
                        // $display("[RAM-CTRL] Restart write");
                        // The data flow was interrupted, so we need to re-issue the
                        // write command when the flow starts again.
                        data_write_issueCmd <= 1;
                    end
                end
                
                Data_State_ReadStart: begin
                    // $display("[RAM-CTRL] Data_State_ReadStart");
                    // Activate the bank+row
                    ramCmd <= RAM_Cmd_BankActivate;
                    ramBA <= data_addr[`BankBits];
                    ramA <= data_addr[`RowBits];
                    
                    data_delayCounter <= Data_BankActivateDelay;
                    data_state <= Data_State_Delay;
                    data_nextState <= Data_State_Read;
                end
                
                Data_State_Read: begin
                    // $display("[RAM-CTRL] Data_State_Read");
                    // $display("[RAM-CTRL] Read mem[%h] = %h", data_addr, write_data);
                    ramA <= data_addr[`ColBits]; // Supply the column address
                    ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                    ramCmd <= RAM_Cmd_Read; // Give read command
                    data_delayCounter <= C_CAS+1; // +1 cycle due to input register
                    data_state <= Data_State_Read+1;
                end
                
                Data_State_Read+1: begin
                    // $display("[RAM-CTRL] Data_State_Read+1");
                    ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                    if (!data_delayCounter) begin
                        read_ready <= 1; // Notify that data is available
                        data_state <= Data_State_Read+2;
                    end
                end
                
                Data_State_Read+2: begin
                    // $display("[RAM-CTRL] Data_State_Read+2");
                    // if (read_ready) $display("[RAM-CTRL] Read mem[%h] = %h", data_addr, read_data);
                    if (read_trigger) begin
                        // $display("[RAM-CTRL] Read mem[%h] = %h", data_addr, read_data);
                        ramDQM <= RAM_DQM_Unmasked; // Unmask the data
                        data_addr <= data_addr+1;
                        
                        // Handle reaching the end of a row or the end of block
                        if (&data_addr[`ColBits]) begin
                            // $display("[RAM-CTRL] End of row / end of block");
                            // Abort reading
                            data_delayCounter <= Data_FinishDelay;
                            data_state <= Data_State_Delay;
                            data_nextState <= Data_State_Finish;
                        end else begin
                            // Notify that more data is available
                            read_ready <= 1;
                        end
                        
                    end else begin
                        // $display("[RAM-CTRL] Restart read");
                        // If the current data wasn't accepted, we need restart reading
                        data_state <= Data_State_Read;
                    end
                end
                
                Data_State_Finish: begin
                    // $display("[RAM-CTRL] Data_State_Finish");
                    ramCmd <= RAM_Cmd_PrechargeAll;
                    ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
                    
                    data_delayCounter <= Clocks(ClkFreq,T_RP,2); // -2 cycles getting to the next state
                    data_state <= Data_State_Delay;
                    data_nextState <= data_restartState;
                end
                
                Data_State_Delay: begin
                    if (!data_delayCounter) data_state <= data_nextState;
                end
                endcase
            end
            
            if (!refresh_counter) begin
                // Override our `_ready` flags if we're refreshing on the next cycle
                write_ready <= 0;
                read_ready <= 0;
                // Trigger refresh
                refresh_trigger <= 1;
            end
        end
        
        // Handle new commands
        if (cmd !== `RAMController_Cmd_None) begin
            // Override our _ready/_done flags if we're starting a new command on the next cycle
            write_ready <= 0;
            read_ready <= 0;
            
            data_addr <= AddrFromBlock(cmd_block);
            
            case (cmd)
            `RAMController_Cmd_Write:   data_restartState <= Data_State_WriteStart;
            `RAMController_Cmd_Read:    data_restartState <= Data_State_ReadStart;
            `RAMController_Cmd_Stop:    data_restartState <= Data_State_Idle;
            endcase
            
            // If `data_state` is _Idle, then we can jump right to _WriteStart/_ReadStart/_Idle.
            // Otherwise, we need to delay since we don't know what state we came from.
            if (data_state === Data_State_Idle) begin
                case (cmd)
                `RAMController_Cmd_Write:   data_state <= Data_State_WriteStart;
                `RAMController_Cmd_Read:    data_state <= Data_State_ReadStart;
                `RAMController_Cmd_Stop:    data_state <= Data_State_Idle;
                endcase
            
            end else begin
                data_delayCounter <= InterruptDelay;
                data_state <= Data_State_Delay;
                data_nextState <= Data_State_Finish;
            end
        end
    end
endmodule

`endif

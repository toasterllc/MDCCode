`ifndef RAMController_v
`define RAMController_v

`include "Delay.v"

module RAMController #(
    parameter ClkFreq               = 24_000_000,
    parameter RAMClkDelay           = 0,
    parameter BlockSize             = 16,
    
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
    
    // TODO: consider re-ordering: cmd_block, cmd_write, cmd_trigger
    // Command port (clock domain: `clk`)
    input wire                  cmd_trigger,    // Start the command
    input wire[BlockWidth-1:0]  cmd_block,      // Block index
    input wire                  cmd_write,      // Read (0) or write (1)
    
    // TODO: consider re-ordering: write_data, write_trigger, write_ready
    // Write port (clock domain: `clk`)
    output reg                  write_ready = 0,    // `write_data` accepted
    input wire                  write_trigger,      // Only effective if `write_ready`=1
    input wire[WordWidth-1:0]   write_data,         // Data to write to RAM
    output reg                  write_done,         // Writing to the block is complete
    
    // TODO: consider re-ordering: read_data, read_trigger, read_ready
    // Read port (clock domain: `clk`)
    output reg                  read_ready = 0,     // `read_data` valid
    input wire                  read_trigger,       // Only effective if `read_ready`=1
    output wire[WordWidth-1:0]  read_data,          // Data read from RAM
    output reg                  read_done,          // Reading from the block is complete
    
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
    assign read_data = ramDQIn;
    
//     // TODO: we need to remove this when testing the RAM with the SDRAM chip sim (mt48h32m16lf)
// `ifdef SIM
//     assign ramDQIn = 0;
// `endif
    
    // ====================
    // Init State Machine Registers
    // ====================
    localparam Init_State_Init              = 0;    // +7
    localparam Init_State_Nop               = 8;    // +0
    localparam Init_State_Delay             = 9;    // +0
    localparam Init_State_Count             = 10;
    localparam Init_State_Width             = `RegWidth(Init_State_Count);
    
    reg[Init_State_Width-1:0] init_state = 0;
    reg[Init_State_Width-1:0] init_nextState = 0;
    
    localparam Init_Delay = Clocks(T_INIT,2); // -2 cycles getting to the next state
    localparam Init_DelayCounterWidth = `RegWidth5(
        // Init states
        Init_Delay,
        10,
        Clocks(T_RP,2),
        Clocks(T_RFC,2),
        `Sub(C_MRD,2)
    );
    reg[Init_DelayCounterWidth-1:0] init_delayCounter = 0;
    reg init_done = 0;
    
    
    
    
    
    
    
    // ====================
    // Refresh State Machine Registers
    // ====================
    localparam Refresh_State_Go     = 0;    // +3
    localparam Refresh_State_Delay  = 4;    // +1
    localparam Refresh_State_Count  = 5;
    localparam Refresh_State_Width  = `RegWidth(Refresh_State_Count);
    localparam Refresh_Delay = Clocks(T_REFI,2);    // -2 cycles:
                                                    //   -1: Because waiting N cycles requires loading a counter with N-1.
                                                    //   -1: Because Clocks() ceils the result, so if we need to
                                                    //       wait 10.5 cycles, Clocks() will return 11, when we
                                                    //       actually want 10. This can cause us to be more
                                                    //       conservative than necessary in the case where refresh period
                                                    //       is an exact multiple of the clock period, but refreshing
                                                    //       one cycle earlier is fine.
    reg[`RegWidth(Refresh_Delay)-1:0] refresh_counter = 0;
    localparam Refresh_StartDelay = `Max6(
        // T_RC: the previous cycle may have issued RAM_Cmd_BankActivate, so prevent violating T_RC
        // when we finish refreshing.
        // -2 cycles getting to the next state
        Clocks(T_RC,2),
        // T_RRD: the previous cycle may have issued RAM_Cmd_BankActivate, so prevent violating T_RRD
        // when we finish refreshing.
        // -2 cycles getting to the next state
        Clocks(T_RRD,2),
        // T_RAS: the previous cycle may have issued RAM_Cmd_BankActivate, so prevent violating T_RAS
        // since we're about to issue CmdPrechargeAll.
        // -2 cycles getting to the next state
        Clocks(T_RAS,2),
        // T_RCD: the previous cycle may have issued RAM_Cmd_BankActivate, so prevent violating T_RCD
        // when we finish refreshing.
        // -2 cycles getting to the next state
        Clocks(T_RCD,2),
        // T_RP: the previous cycle may have issued RAM_Cmd_PrechargeAll, so delay other commands
        // until precharging is complete.
        // -2 cycles getting to the next state
        Clocks(T_RP,2),
        // T_WR: the previous cycle may have issued RAM_Cmd_Write, so delay other commands
        // until precharging is complete.
        // -2 cycles getting to the next state
        Clocks(T_WR,2)
    );
    localparam Refresh_DelayCounterWidth = `RegWidth3(
        Refresh_StartDelay,
        Clocks(T_RP,2),
        Clocks(T_RFC,2)
    );
    reg[Refresh_DelayCounterWidth-1:0] refresh_delayCounter = 0;
    reg[Refresh_State_Width-1:0] refresh_state = 0;
    reg[Refresh_State_Width-1:0] refresh_nextState = 0;
    reg refresh_trigger = 0;
    
    
    
    
    
    
    // ====================
    // Data State Machine Registers
    // ====================
    localparam Data_State_Idle              = 0;    // +0
    localparam Data_State_StartInterrupt    = 1;    // +0
    localparam Data_State_StartPrecharge    = 2;    // +0
    localparam Data_State_Start             = 3;    // +0
    localparam Data_State_Write             = 4;    // +1
    localparam Data_State_Read              = 6;    // +2
    localparam Data_State_Delay             = 9;    // +0
    localparam Data_State_Count             = 10;
    localparam Data_State_Width             = `RegWidth(Data_State_Count);
    
    reg[Data_State_Width-1:0] data_state = 0;
    reg[Data_State_Width-1:0] data_nextState = 0;
    
    localparam Data_Mode_None       = 0;
    localparam Data_Mode_Write      = 1;
    localparam Data_Mode_Read       = 2;
    reg[1:0] data_mode = 0;
    
    reg[AddrWidth-1:0] data_addr = 0;
    reg[BlockSizeCeilLog2-1:0] data_counter = 0;
    
    localparam Data_BankActivateDelay = `Max4(
        // T_RCD: ensure "bank activate to read/write time".
        // -2 cycles getting to the next state
        Clocks(T_RCD,2),
        // T_RAS: ensure "row activate to precharge time", ie that we don't
        // CmdPrechargeAll too soon after we activate the bank.
        // -2 cycles getting to the next state
        Clocks(T_RAS,2),
        // T_RC: ensure "activate bank A to activate bank A time", to ensure that the next
        // bank can't be activated too soon after this bank activation.
        // -2 cycles getting to the next state
        Clocks(T_RC,2),
        // T_RRD: ensure "activate bank A to activate bank B time", to ensure that the next
        // bank can't be activated too soon after this bank activation.
        // -2 cycles getting to the next state
        Clocks(T_RRD,2)
    );
    localparam Data_DelayCounterWidth = `RegWidth4(
        Data_BankActivateDelay,
        Clocks(T_WR,2),
        C_CAS+1,
        Clocks(T_RP,2)
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
        write_done <= 0;
        read_ready <= 0;
        read_done <= 0;
        
        
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
            
            init_delayCounter <= Clocks(T_RP,2); // -2 cycles getting to the next state
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
            init_delayCounter <= Clocks(T_RFC,2); // -2 cycles getting to the next state
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
            init_delayCounter <= Clocks(T_RFC,2); // Delay T_RFC; -2 cycles getting to the next state
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
            
            init_delayCounter <= `Sub(C_MRD,2); // -2 cycles getting to the next state
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
                    $display("[RAM-CTRL] Refresh start");
                    // We don't know what state we came from, so wait the most conservative amount of time.
                    refresh_delayCounter <= Refresh_StartDelay;
                    refresh_state <= Refresh_State_Delay;
                    refresh_nextState <= Refresh_State_Go+1;
                end
                
                Refresh_State_Go+1: begin
                    // Precharge all banks
                    ramCmd <= RAM_Cmd_PrechargeAll;
                    ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
                
                    // Wait T_RP (precharge to refresh/row activate) until we can issue CmdAutoRefresh
                    refresh_delayCounter <= Clocks(T_RP,2); // -2 cycles getting to the next state
                    refresh_state <= Refresh_State_Delay;
                    refresh_nextState <= Refresh_State_Go+2;
                end
                
                Refresh_State_Go+2: begin
                    $display("[RAM-CTRL] Refresh (time: %0d)", $time);
                    // Issue auto-refresh command
                    ramCmd <= RAM_Cmd_AutoRefresh;
                    // Wait T_RFC (auto refresh time) to guarantee that the next command can
                    // activate the same bank immediately
                    refresh_delayCounter <= Clocks(T_RFC,3); // -2 cycles getting to the next state
                    refresh_state <= Refresh_State_Delay;
                    refresh_nextState <= Refresh_State_Go+3;
                end
                
                Refresh_State_Go+3: begin
                    refresh_state <= Refresh_State_Go;
                    refresh_trigger <= 0;
                    // Restart the current command, if there was one in progress
                    case (data_mode)
                    Data_Mode_None: data_state <= Data_State_Idle;
                    default:        data_state <= Data_State_Start;
                    endcase
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
                
                Data_State_StartInterrupt: begin
                    // TODO: figure out a better name for `Refresh_StartDelay` since we're using it here
                    data_delayCounter <= Refresh_StartDelay;
                    data_state <= Data_State_Delay;
                    data_nextState <= Data_State_StartPrecharge;
                end
                
                Data_State_StartPrecharge: begin
                    // $display("[RAM-CTRL] Data_State_StartPrecharge");
                    ramCmd <= RAM_Cmd_PrechargeAll;
                    ramA <= 'b10000000000; // ram_a[10]=1 for PrechargeAll
                    
                    // After precharge completes, continue writing if there's more data
                    data_delayCounter <= Clocks(T_RP,2); // -2 cycles getting to the next state
                    data_state <= Data_State_Delay;
                    data_nextState <= (data_mode===Data_Mode_None ? Data_State_Idle : Data_State_Start);
                end
                
                Data_State_Start: begin
                    // $display("[RAM-CTRL] Data_State_Start");
                    // Activate the bank+row
                    ramCmd <= RAM_Cmd_BankActivate;
                    ramBA <= data_addr[`BankBits];
                    ramA <= data_addr[`RowBits];
                    
                    data_write_issueCmd <= 1; // The first write needs to issue the write command
                    data_delayCounter <= Data_BankActivateDelay;
                    data_state <= Data_State_Delay;
                    data_nextState <= (data_mode===Data_Mode_Write ? Data_State_Write : Data_State_Read);
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
                        data_counter <= data_counter-1;
                        data_write_issueCmd <= 0; // Reset after we issue the write command
                        
                        if (!data_counter) begin
                            // Signal that we're done
                            write_done <= 1;
                            // Clear data_mode because we're done
                            data_mode <= Data_Mode_None;
                        end
                        
                        // Handle reaching the end of a row or the end of block
                        if (&data_addr[`ColBits] || !data_counter) begin
                            // $display("[RAM-CTRL] End of row / end of block");
                            // Override `write_ready=1` above since we can't handle new data in the next state
                            write_ready <= 0;
                            
                            // Abort writing
                            // Wait the 'write recover' time before doing so.
                            // Datasheet (paraphrased):
                            //   "The PrechargeAll command that interrupts a write burst should be
                            //   issued ceil(tWR/tCK) cycles after the clock edge in which the
                            //   last data-in element is registered."
                            data_delayCounter <= Clocks(T_WR,2); // -2 cycles getting to Data_State_StartPrecharge
                            data_state <= Data_State_Delay;
                            data_nextState <= Data_State_StartPrecharge;
                        end
                        
                    end else begin
                        // $display("[RAM-CTRL] Restart write");
                        // The data flow was interrupted, so we need to re-issue the
                        // write command when the flow starts again.
                        data_write_issueCmd <= 1;
                    end
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
                        data_counter <= data_counter-1;
                        
                        if (!data_counter) begin
                            // Signal that we're done
                            read_done <= 1;
                            // Clear data_mode because we're done
                            data_mode <= Data_Mode_None;
                        end
                        
                        // Handle reaching the end of a row or the end of block
                        if (&data_addr[`ColBits] || !data_counter) begin
                            // $display("[RAM-CTRL] End of row / end of block");
                            // Abort reading
                            data_state <= Data_State_StartPrecharge;
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
        if (cmd_trigger) begin
            // Override our `_ready` flags if we're starting a new command on the next cycle
            write_ready <= 0;
            read_ready <= 0;
            
            data_addr <= AddrFromBlock(cmd_block);
            data_counter <= BlockSize-1;
            data_mode <= (cmd_write ? Data_Mode_Write : Data_Mode_Read);
            // If `data_state` is _Idle, then we can jump right to _Start.
            // Otherwise, we need to delay going to _Start, since we don't
            // know what state we came from.
            // TODO: if this executes on the cycle before the refresh is finished, the Data_State_StartInterrupt will get overridden by the refresh with Data_State_Start, which is kinda gross.
            // TODO: if a command is triggered after write_done is signalled, we'll likely be delaying T_WR, which will cause us to wait a long time in Data_State_StartInterrupt, when we only needed to wait T_WR.
            data_state <= (data_state===Data_State_Idle ? Data_State_Start : Data_State_StartInterrupt);
        end
    end
endmodule

`endif

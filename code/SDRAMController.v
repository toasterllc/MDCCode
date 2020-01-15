`define DO_REFRESH

module SDRAMController(
    input logic clk,                // Clock
    input logic rst,                // Reset (synchronous)
    
    // Command port
    output logic cmdReady,          // Ready for new command
    input logic cmdTrigger,         // Start the command
    input logic cmdWrite,           // Read (0) or write (1)
    input logic[22:0] cmdAddr,      // Address
    input logic[15:0] cmdWriteData, // Data to write to address
    output logic[15:0] cmdReadData, // Data read from address
    output logic cmdReadDataValid,  // `cmdReadData` is valid data
    output logic didRefresh,
    
    // SDRAM port
    output logic sdram_clk,         // Clock
    output logic sdram_cke,         // Clock enable
    output logic[1:0] sdram_ba,     // Bank address
    output logic[11:0] sdram_a,     // Address
    output logic sdram_cs_,         // Chip select
    output logic sdram_ras_,        // Row address strobe
    output logic sdram_cas_,        // Column address strobe
    output logic sdram_we_,         // Write enable
    output logic sdram_ldqm,        // Low byte data mask
    output logic sdram_udqm,        // High byte data mask
    inout logic[15:0] sdram_dq      // Data input/output
);
    
    // localparam ClockFrequency = 12000000;
    parameter ClockFrequency = 12000000;
    // 366,300
    // localparam ClockFrequency = 739645;
    // localparam ClockFrequency = 5952380;
    // localparam ClockFrequency = 754148;
    localparam DelayCounterWidth = $clog2(Clocks(T_RFC));
    // Size refreshCounter so it'll fit Clocks(T_INIT) when combined with delayCounter
    localparam RefreshCounterWidth = $clog2(Clocks(T_INIT))-DelayCounterWidth;
    localparam StateWidth = 3;
    
    // Alliance AS4C8M16SA Timing parameters (nanoseconds)
    localparam T_INIT = 200000; // power up initialization time
    localparam T_REFI = 15625; // time between refreshes
    localparam T_RC = 63; // bank activate to bank activate time (same bank)
    localparam T_RFC = 63; // refresh time // TODO: we dont know what this is for our Alliance SDRAM
                                            // TODO: maybe increasing this value would make Alliance SDRAM work?
    localparam T_RRD = 14; // row activate to row activate time (different banks)
    localparam T_RAS = 42; // row activate to precharge time (same bank)
    localparam T_RCD = 21; // bank activate to read/write time (same bank)
    localparam T_RP = 21; // precharge to refresh/row activate (same bank)
    localparam T_WR = 14; // write recover time
    
    // // Micron 48LC16M16A2 Timing parameters (nanoseconds)
    // localparam T_INIT = ; // power up initialization time
    // localparam T_REFI = ; // time between refreshes
    // localparam T_RC = ; // bank activate to bank activate time (same bank)
    // localparam T_RFC = ; // refresh time // TODO: we dont know what this is for our Alliance SDRAM
    //                                         // TODO: maybe increasing this value would make Alliance SDRAM work?
    // localparam T_RRD = ; // row activate to row activate time (different banks)
    // localparam T_RAS = ; // row activate to precharge time (same bank)
    // localparam T_RCD = ; // bank activate to read/write time (same bank)
    // localparam T_RP = ; // precharge to refresh/row activate (same bank)
    // localparam T_WR = ; // write recover time
    
    // Timing parameters (clock cycles)
    localparam C_CAS = 2; // Column address strobe (CAS) delay
    localparam C_DQZ = 2; // (T_DQZ) DQM to data high-impedance during reads delay
    localparam C_MRD = 2; // (T_MRD) set mode command to bank activate/refresh command delay
    
    // ras_, cas_, we_
    localparam CmdSetMode           = 3'b000;
    localparam CmdAutoRefresh       = 3'b001;
    localparam CmdPrechargeAll      = 3'b010;
    localparam CmdBankActivate      = 3'b011;
    localparam CmdWrite             = 3'b100;
    localparam CmdRead              = 3'b101;
    localparam CmdNop               = 3'b111;
    
    localparam StateInit            = 3'h0;
    localparam StateRefresh         = 3'h1;
    localparam StateIdle            = 3'h2;
    localparam StateHandleSaved     = 3'h3;
    localparam StateWrite           = 3'h4;
    localparam StateWriteAbort      = 3'h5;
    localparam StateRead            = 3'h6;
    localparam StateReadAbort       = 3'h7;
    
    function integer Clocks;
        // Icarus Verilog doesn't support `logic` type for arguments for
        // some reason, so use `reg` instead.
        // We can't use `integer` because it's only 32 bits.
        input reg[63:0] t;
        Clocks = (t*ClockFrequency)/1000000000;
    endfunction
    
    function integer Max;
        input integer a;
        input integer b;
        Max = (a > b ? a : b);
    endfunction
    
    logic[StateWidth-1:0] state;
    logic[3:0] substate;
    logic[DelayCounterWidth-1:0] delayCounter;
    logic[RefreshCounterWidth-1:0] refreshCounter;
    
    logic[DelayCounterWidth+RefreshCounterWidth-1:0] initDelayCounter;
    assign initDelayCounter = {delayCounter, refreshCounter};
    
    // cmdReady==true in the states where we invoke SaveCommand().
    // In other words, cmdReady==true when we're going to store the incoming command.
    assign cmdReady = (
        delayCounter==0 &&
`ifdef DO_REFRESH
        refreshCounter!=0 &&
`endif
        (state==StateIdle || state==StateRead || state==StateWrite));
    
    logic writeDataValid;
    logic[C_CAS:0] readDataValidShiftReg;
    assign cmdReadDataValid = readDataValidShiftReg[0];
    
    logic[1:0] cmdAddrBank;
    logic[11:0] cmdAddrRow;
    logic[8:0] cmdAddrCol;
    assign cmdAddrBank = cmdAddr[22:21];
    assign cmdAddrRow = cmdAddr[20:9];
    assign cmdAddrCol = cmdAddr[8:0];
    
    logic savedCmdTrigger;
    logic savedCmdWrite;
    logic[22:0] savedCmdAddr;
    logic[15:0] savedCmdWriteData;
    
    logic[1:0] savedCmdAddrBank;
    logic[11:0] savedCmdAddrRow;
    logic[8:0] savedCmdAddrCol;
    assign savedCmdAddrBank = savedCmdAddr[22:21];
    assign savedCmdAddrRow = savedCmdAddr[20:9];
    assign savedCmdAddrCol = savedCmdAddr[8:0];
    
    // ## SDRAM nets
    assign sdram_clk = clk;
    assign sdram_cs_ = 0;
    
    logic[2:0] sdram_cmd;
    assign sdram_ras_ = sdram_cmd[2];
    assign sdram_cas_ = sdram_cmd[1];
    assign sdram_we_ = sdram_cmd[0];
    
    logic sdram_dqm;
    assign sdram_ldqm = sdram_dqm;
    assign sdram_udqm = sdram_dqm;
    
    logic[15:0] sdram_writeData;
    
    // Hook up cmdReadData/sdram_writeData to sdram_dq
    genvar i;
    for (i=0; i<16; i=i+1) begin
        `ifdef SYNTH
            // For synthesis, we have to use a SB_IO for a tristate buffer
            SB_IO #(
                .PIN_TYPE(6'b1010_01),
                .PULLUP(0),
            ) dqio (
                .PACKAGE_PIN(sdram_dq[i]),
                .OUTPUT_ENABLE(writeDataValid),
                .D_OUT_0(sdram_writeData[i]),
                .D_IN_0(cmdReadData[i]),
            );
        `else
            // For simulation, use a normal tristate buffer
            assign sdram_dq[i] = (writeDataValid ? sdram_writeData[i] : 1'bz);
            assign cmdReadData[i] = sdram_dq[i];
        `endif
    end
    
    task StartState(input integer delay, input integer newState);
        delayCounter <= delay;
        state <= newState;
        substate <= 0;
    endtask
    
    task NextSubstate(input integer delay);
        delayCounter <= delay;
        substate <= substate+1;
    endtask
    
    task SaveCommand;
        // Save the command
        savedCmdTrigger <= cmdTrigger;
        // Don't clobber the previously saved command if we're not triggering,
        // so we can refer to `savedCmdAddr` to tell what address is active.
        if (cmdTrigger) begin
            savedCmdWrite <= cmdWrite;
            savedCmdAddr <= cmdAddr;
            savedCmdWriteData <= cmdWriteData;
        end
    endtask
    
    task PrechargeAll;
        sdram_cmd <= CmdPrechargeAll;
        sdram_a <= 12'b010000000000; // sdram_a[10]=1 for PrechargeAll
    endtask
    
    task HandleWrite(input logic substate);
        // Save the incoming command
        SaveCommand();
        
        if (savedCmdTrigger) begin
            // Supply the column address
            sdram_a <= {3'b000, savedCmdAddrCol};
            // Supply data to be written
            sdram_writeData <= savedCmdWriteData;
            // Unmask the data
            sdram_dqm <= 0;
            
            // Supply the write command
            if (substate==0) sdram_cmd <= CmdWrite;
            
            writeDataValid <= 1;
        end
        
        if (cmdTrigger) begin
            // Continue writing if we're writing to the same bank and row
            if (cmdAddrBank==savedCmdAddrBank && cmdAddrRow==savedCmdAddrRow) begin
                // Continue writing
                if (cmdWrite) begin
                    // The column isn't the next sequential column: issue a new write command
                    if (cmdAddrCol != savedCmdAddrCol+1) StartState(0, StateWrite);
                    // The column is the next sequential column: enter sequential-write substate
                    else if (substate == 0) NextSubstate(0);
                
                // Transition to reading
                // Wait Clocks(T_WR) before transitioning to StateRead to avoid the read state
                // allowing us to precharge too soon after a write (which would violate T_WR).
                // -1 clock cycle since we know StateRead will eat one cycle before allowing
                // a precharge via StateReadAbort.
                end else StartState(Max(0, Clocks(T_WR)-1), StateRead);
            
            // Abort the write if we're not writing to the same bank and row.
            // Wait the 'write recover' time before doing so.
            // Datasheet (paraphrased):
            // "The PrechargeAll command that interrupts a write burst should be
            // issued ceil(tWR/tCK) cycles after the clock edge in which the
            // last data-in element is registered."
            end else StartState(Max(0, Clocks(T_WR)), StateWriteAbort);
        end
    endtask
    
    task HandleRead(input logic substate);
        // Save the incoming command
        SaveCommand();
        
        if (savedCmdTrigger) begin
            // Supply the column address
            sdram_a <= {3'b000, savedCmdAddrCol};
            // Unmask the data
            sdram_dqm <= 0;
            
            // Supply the read command
            if (substate==0) sdram_cmd <= CmdRead;
            
            readDataValidShiftReg[C_CAS] <= 1;
        end
        
        if (cmdTrigger) begin
            // Continue reading if we're reading from the same bank and row
            if (cmdAddrBank==savedCmdAddrBank && cmdAddrRow==savedCmdAddrRow) begin
                // Continue reading
                if (!cmdWrite) begin
                    // The column isn't the next sequential column: issue a new read command
                    if (cmdAddrCol != savedCmdAddrCol+1) StartState(0, StateRead);
                    // The column is the next sequential column: enter sequential-read substate
                    else if (substate == 0) NextSubstate(0);
                
                // Transition to writing
                // Wait `C_DQZ+1` cycles before doing so to ensure DQs are high-Z. +1 cycle because
                // "at least a single-cycle delay should occur between the last read data and
                // the WRITE command".
                // 2/24: verified that we have 1 cycle between SDRAM driving DQs (due to read)
                //       and us driving DQs (due to write)
                end else StartState(C_DQZ+1, StateWrite);
            
            // Abort the read if we're not reading from the same bank and row
            end else StartState(0, StateReadAbort);
        end
    endtask
    
    task SetDefaultState;
        // Mask data, nop command
        sdram_dqm <= 1;
        sdram_cmd <= CmdNop;
        
        // Update data-valid registers
        writeDataValid <= 0;
        readDataValidShiftReg[C_CAS:0] <= {1'b0, readDataValidShiftReg[C_CAS:1]};
        
        // Update counters
        delayCounter <= (delayCounter!=0 ? delayCounter-1 : 0);
        refreshCounter <= (refreshCounter!=0 ? refreshCounter-1 : Max(0, Clocks(T_REFI)-1));
    endtask
    
    task StartReadWrite(input logic write, input logic[22:0] addr);
        // Activate the bank+row
        sdram_cmd <= CmdBankActivate;
        sdram_ba <= addr[22:21];
        sdram_a <= addr[20:9];
        
        // Delay the most conservative amount of time necessary after activating the bank to perform the command.
        StartState(Max(0, Max(Max(Max(
            // T_RCD: ensure "bank activate to read/write time".
            Clocks(T_RCD),
            // T_RAS: ensure "row activate to precharge time", ie that we don't
            // CmdPrechargeAll too soon after we activate the bank.
            // -2 cycles since we know that it takes >=2 state transitions from this state
            // to issue CmdPrechargeAll (StateIdle/StateHandleSaved -> StateRead/StateWrite ->
            // StateReadAbort/StateWriteAbort)
            Clocks(T_RAS)-2),
            // T_RC: ensure "activate bank A to activate bank A time", to ensure that the next
            // bank can't be activated too soon after this bank activation.
            // -3 cycles since we know that it takes >=3 state transitions from this state to
            // reach this state again and issue another CmdBankActivate (StateIdle/StateHandleSaved ->
            // StateRead/StateWrite -> StateReadAbort/StateWriteAbort -> StateIdle/StateHandleSaved)
            Clocks(T_RC)-3),
            // T_RRD: ensure "activate bank A to activate bank B time", to ensure that the next
            // bank can't be activated too soon after this bank activation.
            // -3 cycles since we know that it takes >=3 state transitions from this state to
            // reach this state again and issue another CmdBankActivate (see explanation for T_RC, above.)
            Clocks(T_RRD)-3)),
        (write ? StateWrite : StateRead));
    endtask
    
    // initial $display("Max(Clocks(T_RCD), Clocks(T_RAS)-2): %d", Max(Clocks(T_RCD), Clocks(T_RAS)-2));
    // initial $finish;
    
    task InitSetDelayCounter(input integer delay);
        {delayCounter, refreshCounter} <= delay;
    endtask
    
    task InitStartState(input integer delay);
        InitSetDelayCounter(delay);
        state <= StateInit;
        substate <= 0;
    endtask
    
    task InitNextSubstate(input integer delay);
        InitSetDelayCounter(delay);
        substate <= substate+1;
    endtask
    
    task HandleReset;
        // Reset the important registers while in the reset state.
        // This is necessary so clients don't observe `cmdReadDataValid`
        // immediately after reset de-asserts but before the HandleInit
        // state machine starts.
        writeDataValid <= 0;
        readDataValidShiftReg <= 0;
        InitStartState(0);
        
        didRefresh <= 0;
    endtask
    
    task HandleInit;
        // Handle delays
        if (initDelayCounter != 0) begin
            sdram_cmd <= CmdNop;
            InitSetDelayCounter(initDelayCounter-1);
        
        // Handle init states
        end else case (substate)
            0: begin
                // Initialize registers
                sdram_cke <= 0;
                sdram_dqm <= 1;
                sdram_cmd <= CmdNop;
                // Delay 200us
                InitNextSubstate(Clocks(T_INIT));
            end
            
            1: begin
                // Bring sdram_cke high for a bit before issuing commands
                sdram_cke <= 1;
                InitNextSubstate(10);
            end
            
            2: begin
                // Precharge all banks
                PrechargeAll();
                InitNextSubstate(Clocks(T_RP));
            end
            
            3: begin
                // Set the operating mode of the SDRAM
                sdram_cmd <= CmdSetMode;
                // sdram_ba:    reserved
                sdram_ba <=     2'b0;
                // sdram_a:     reserved,   write burst length,     test mode,  CAS latency,    burst type,     burst length
                sdram_a <= {    2'b0,       1'b0,                   2'b0,       3'b010,         1'b0,           3'b111};
                // We need a delay of C_MRD clock cycles before issuing the next command
                // -1 clock cycle since we already burn one cycle getting to the next substate.
                InitNextSubstate(Max(0, C_MRD-1));
            end
            
            4: begin
                // Autorefresh 1/2
                sdram_cmd <= CmdAutoRefresh;
                // Wait T_RFC for autorefresh to complete
                // The docs say it takes T_RFC for AutoRefresh to complete, but T_RP must be met
                // before issuing successive AutoRefresh commands. Because T_RFC>T_RP, assume
                // we just have to wait T_RFC.
                InitNextSubstate(Clocks(T_RFC));
            end
            
            5: begin
                // Autorefresh 2/2
                sdram_cmd <= CmdAutoRefresh;
                
                // Start the refresh timer
                refreshCounter <= Max(0, Clocks(T_REFI)-1);
                
                // Wait T_RFC for autorefresh to complete
                // The docs say it takes T_RFC for AutoRefresh to complete, but T_RP must be met
                // before issuing successive AutoRefresh commands. Because T_RFC>T_RP, I'm
                // assuming we just have to wait T_RFC.
                // ## Use StartState() (not InitStartState()) because the next state isn't an
                // ## init state (StateInitXXX), and we don't want to clobber refreshCounter.
                StartState(Clocks(T_RFC), StateIdle);
            end
            endcase
    endtask
    
    task HandleRefresh;
        SetDefaultState();
        
        // Initiate refresh when refreshCounter==0
        if (refreshCounter == 0)
            
            // We don't know what state we came from, so wait the most conservative amount of time.
            StartState(Max(0, Max(Max(Max(Max(Max(
                // T_RC: the previous cycle may have issued CmdBankActivate, so prevent violating T_RC
                // when we return to that command via StateHandleSaved after refreshing is complete.
                Clocks(T_RC),
                // T_RRD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RRD
                // when we return to that command via StateHandleSaved after refreshing is complete.
                Clocks(T_RRD)),
                // T_RAS: the previous cycle may have issued CmdBankActivate, so prevent violating T_RAS
                // since we're about to issue CmdPrechargeAll.
                Clocks(T_RAS)),
                // T_RCD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RCD
                // when we return to that command via StateHandleSaved after refreshing is complete.
                Clocks(T_RCD)),
                // T_RP: the previous cycle may have issued CmdPrechargeAll, so delay other commands
                // until precharging is complete.
                Clocks(T_RP)),
                // T_WR: the previous cycle may have issued CmdWrite, so delay other commands
                // until precharging is complete.
                Clocks(T_WR))-1) // -1 because we spent a cycle in this state
            , StateRefresh);
            
        // Handle Refresh states
        else if (delayCounter == 0)
            case (substate)
            0: begin
                PrechargeAll();
                // Wait T_RP (precharge to refresh/row activate) until we can issue CmdAutoRefresh
                NextSubstate(Clocks(T_RP));
            end
            
            1: begin
                sdram_cmd <= CmdAutoRefresh;
                // Wait T_RFC (auto refresh time) to guarantee that the next command can
                // activate the same bank immediately
                StartState(Clocks(T_RFC), (savedCmdTrigger ? StateHandleSaved : StateIdle));
                didRefresh <= !didRefresh;
            end
            endcase
    endtask
    
    task HandleCommand;
        SetDefaultState();
        
        // Handle commands
        if (delayCounter == 0) begin
            case (state)
            StateIdle: begin
                SaveCommand();
                if (cmdTrigger) StartReadWrite(cmdWrite, cmdAddr);
            end
            
            StateHandleSaved:
                StartReadWrite(savedCmdWrite, savedCmdAddr);
            
            StateWrite:
                HandleWrite(substate);
            
            StateWriteAbort: begin
                PrechargeAll();
                // After precharge completes, handle the saved command or
                // go idle if there isn't a saved command
                StartState(Clocks(T_RP), (savedCmdTrigger ? StateHandleSaved : StateIdle));
            end
            
            StateRead:
                HandleRead(substate);
            
            StateReadAbort: begin
                PrechargeAll();
                // After precharge completes, handle the saved command or go idle
                // if there isn't a saved command.
                // Wait for precharge to complete, or for the data to finish reading
                // out, whichever takes longer.
                // Use C_CAS-1 because we already spent one clock cycle of the CAS
                // latency in this state.
                StartState(Max(C_CAS-1, Clocks(T_RP)), (savedCmdTrigger ? StateHandleSaved : StateIdle));
            end
            endcase
        end
    endtask
    
	always @(posedge clk) begin
        // Reset
        if (rst)
            HandleReset();
        
        // Initialization
        else if (state == StateInit)
            HandleInit();
        
`ifdef DO_REFRESH
        // Refresh
        else if (refreshCounter==0 || state==StateRefresh)
            HandleRefresh();
`endif
        
        // Commands
        else
            HandleCommand();
    end
endmodule

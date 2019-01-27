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
    
    localparam ClockFrequency = 100000000;
    localparam DelayCounterWidth = $clog2(Clocks(T_RC));
    // Size refreshCounter so it'll fit Clocks(T_INIT) when combined with delayCounter
    localparam RefreshCounterWidth = $clog2(Clocks(T_INIT))-DelayCounterWidth;
    localparam StateWidth = 4;
    
    // Timing parameters (nanoseconds)
    localparam T_INIT = 200000; // power up initialization time
    localparam T_REFI = 15625; // max time between refreshes
    localparam T_RC = 63; // bank activate to bank activate (same bank)
    localparam T_RRD = 14; // row activate to row activate (different banks)
    localparam T_RAS = 42; // row activate to precharge time (same bank)
    localparam T_RCD = 21; // bank activate to read/write time (same bank)
    localparam T_RP = 21; // precharge to refresh/row activate (same bank)
    localparam T_WR = 14; // write recover time
    
    // Timing parameters (clock cycles)
    localparam C_CAS = 2; // Column address strobe (CAS) latency
    
    // ras_, cas_, we_
    localparam CmdSetMode       = 3'b000;
    localparam CmdAutoRefresh   = 3'b001;
    localparam CmdPrechargeAll  = 3'b010;
    localparam CmdBankActivate  = 3'b011;
    localparam CmdWrite         = 3'b100;
    localparam CmdRead          = 3'b101;
    localparam CmdNop           = 3'b111;
    
    localparam StateInit4               = 4'h0;
    localparam StateInit3               = 4'h1;
    localparam StateInit2               = 4'h2;
    localparam StateInit1               = 4'h3;
    localparam StateInit0               = 4'h4;
    localparam StateRefresh1            = 4'h5;
    localparam StateRefresh0            = 4'h6;
    localparam StateIdle                = 4'h7;
    localparam StateHandleSaved         = 4'h8;
    localparam StateWrite1              = 4'h9;
    localparam StateWrite0              = 4'hA;
    localparam StateWriteAbort1         = 4'hB;
    localparam StateWriteAbort0         = 4'hC;
    localparam StateRead1               = 4'hD;
    localparam StateRead0               = 4'hE;
    localparam StateReadAbort           = 4'hF;
    
    function integer Clocks;
        // Icarus Verilog doesn't support `logic` type for arguments for some reason, so use `reg` instead.
        input reg[63:0] t;
        Clocks = (t*ClockFrequency)/1000000000;
    endfunction
    
    function integer Max;
        // Icarus Verilog doesn't support `logic` type for arguments for some reason, so use `reg` instead.
        input reg[63:0] a;
        input reg[63:0] b;
        Max = (a > b ? a : b);
    endfunction
    
    logic[StateWidth-1:0] state;
    logic[DelayCounterWidth-1:0] delayCounter;
    logic[RefreshCounterWidth-1:0] refreshCounter;
    
    logic[DelayCounterWidth+RefreshCounterWidth-1:0] initCounter;
    assign initCounter = {delayCounter, refreshCounter};
    
    logic idleState;
    assign idleState = (state==StateIdle);
    
    logic initState;
    assign initState = (state>=StateInit4 && state<=StateInit0);
    
    logic refreshState;
    assign refreshState = (state==StateRefresh1 || state==StateRefresh0);
    
    logic readState;
    assign readState = (state==StateRead1 || state==StateRead0);
    
    logic writeState;
    assign writeState = (state==StateWrite1 || state==StateWrite0);
    
    // cmdReady==true in the states where we invoke SaveCommand().
    // In other words, cmdReady==true when we're going to store the incoming command.
    assign cmdReady = (delayCounter==0 && refreshCounter!=0 && (idleState || readState || writeState));
    
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
    
    logic[22:0] activeAddr;
    logic[1:0] activeAddrBank;
    logic[11:0] activeAddrRow;
    logic[8:0] activeAddrCol;
    assign activeAddrBank = activeAddr[22:21];
    assign activeAddrRow = activeAddr[20:9];
    assign activeAddrCol = activeAddr[8:0];
    
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
    logic[15:0] sdram_readData;
    
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
                .D_IN_0(sdram_readData[i]),
            );
        `else
            // For simulation, use a normal tristate buffer
            assign sdram_dq[i] = (writeDataValid ? sdram_writeData[i] : 1'bz);
            assign cmdReadData[i] = sdram_dq[i];
        `endif
    end
    
    task NextState(input integer n, input integer s);
        delayCounter <= n;
        state <= s;
    endtask
    
    task SaveCommand;
        // Save the command
        savedCmdTrigger <= cmdTrigger;
        savedCmdWrite <= cmdWrite;
        savedCmdAddr <= cmdAddr;
        savedCmdWriteData <= cmdWriteData;
    endtask
    
    task PrechargeAll;
        sdram_cmd <= CmdPrechargeAll;
        sdram_a <= 12'b010000000000; // sdram_a[10]=1 for PrechargeAll
    endtask
    
    task HandleWrite(input logic first);
        // Save the incoming command
        SaveCommand();
        
        // Supply the column address
        sdram_a <= {3'b000, savedCmdAddrCol};
        // Supply data to be written
        sdram_writeData <= savedCmdWriteData;
        // Unmask the data
        sdram_dqm <= 0;
        // Supply the write command, or Nop if this isn't the first write iteration
        sdram_cmd <= (first ? CmdWrite : CmdNop);
        
        writeDataValid <= 1;
        
        // Continue writing if we're writing to the next word
        if (cmdTrigger &&
            cmdWrite &&
            cmdAddrBank==activeAddrBank &&
            cmdAddrRow==activeAddrRow &&
            cmdAddrCol==activeAddrCol+1) begin
            
            // Update active address
            activeAddr <= cmdAddr;
            
            // Continue writing
            NextState(0, StateWrite0);
        
        // Otherwise abort the write
        end else begin
            // Start aborting the write
            NextState(0, StateWriteAbort1);
        end
    endtask
    
    task HandleRead(input logic first);
        // Save the incoming command
        SaveCommand();
        
        // Supply the column address
        sdram_a <= {3'b000, savedCmdAddrCol};
        // Unmask the data
        sdram_dqm <= 0;
        // Supply the read command, or Nop if this isn't the first read iteration
        sdram_cmd <= (first ? CmdRead : CmdNop);
        
        readDataValidShiftReg[C_CAS] <= 1;
        
        // Continue reading if we're reading from the next word
        if (cmdTrigger &&
            !cmdWrite &&
            cmdAddrBank==activeAddrBank &&
            cmdAddrRow==activeAddrRow &&
            cmdAddrCol==activeAddrCol+1) begin
            
            // Update active address
            activeAddr <= cmdAddr;
            
            // Continue reading
            NextState(0, StateRead0);
        
        // Otherwise abort the read
        end else begin
            // Start aborting the read
            NextState(0, StateReadAbort);
        end
    endtask
    
    task UpdateCounters;
        delayCounter <= (delayCounter!=0 ? delayCounter-1 : 0);
        refreshCounter <= (refreshCounter!=0 ? refreshCounter-1 : Clocks(T_REFI)-1);
        writeDataValid <= 0;
        readDataValidShiftReg[C_CAS:0] <= {1'b0, readDataValidShiftReg[C_CAS:1]};
    endtask
    
    task PrepareReadWrite(input logic[22:0] addr);
        // TODO: we need to guarantee that T_RC/T_RRD are met when activating a bank
        // TODO: we need to guarantee that T_RAS is met -- it won't be if we CmdPrechargeAll too soon after we CmdBankActivate. should we just wait T_RAS here?
        // Activate the bank+row
        sdram_cmd <= CmdBankActivate;
        sdram_ba <= addr[22:21];
        sdram_a <= addr[20:9];
        
        // Update active address
        activeAddr <= addr;
        
        // Delay T_RCD clocks after activating the bank to perform the command
        NextState(Clocks(T_RCD), (cmdWrite ? StateWrite1 : StateRead1));
    endtask
    
    task SetInitCounter(input integer n);
        {delayCounter, refreshCounter} <= n;
    endtask
    
    task NextStateInit(input integer n, input integer s);
        SetInitCounter(n);
        state <= s;
    endtask
    
    task HandleInit;
        // Handle delays
        if (initCounter != 0) begin
            sdram_cmd <= CmdNop;
            SetInitCounter(initCounter-1);
        
        // Handle init states
        end else case (state)
        StateInit4: begin
            readDataValidShiftReg <= 0;
            sdram_cke <= 0;
            sdram_dqm <= 1;
            sdram_cmd <= CmdNop;
            // Delay 200us
            NextStateInit(Clocks(T_INIT), StateInit3);
        end
        
        StateInit3: begin
            // Precharge all banks
            sdram_cke <= 1;
            PrechargeAll();
            NextStateInit(Clocks(T_RP), StateInit2);
        end
        
        StateInit2: begin
            // Set the operating mode of the SDRAM
            sdram_cmd <= CmdSetMode;
            // sdram_ba:    reserved
            sdram_ba <=     2'b0;
            // sdram_a:     reserved,   write burst length,     test mode,  CAS latency,    burst type,     burst length
            sdram_a <= {    2'b0,       1'b0,                   2'b0,       3'b010,         1'b0,           3'b111};
            // We have to wait 2 clock cycles before issuing the next command, so inject
            // 1 clock cycle before going to the next state
            NextStateInit(1, StateInit1);
        end
        
        StateInit1: begin
            // Autorefresh 1/2
            sdram_cmd <= CmdAutoRefresh;
            // Wait TRC for autorefresh to complete
            // The docs say it takes TRC for AutoRefresh to complete, but T_RP must be met
            // before issuing successive AutoRefresh commands. Because TRC>T_RP, I'm
            // assuming we just have to wait TRC.
            NextStateInit(Clocks(T_RC), StateInit0);
        end
        
        StateInit0: begin
            // Autorefresh 2/2
            sdram_cmd <= CmdAutoRefresh;
            
            // Prepare refresh timer
            refreshCounter <= Clocks(T_REFI)-1;
            
            // Wait TRC for autorefresh to complete
            // The docs say it takes TRC for AutoRefresh to complete, but T_RP must be met
            // before issuing successive AutoRefresh commands. Because TRC>T_RP, I'm
            // assuming we just have to wait TRC.
            // ## Use NextState() (not NextStateInit()) because the next state isn't an
            // ## init state (StateInitXXX), and we don't want to clobber refreshCounter.
            NextState(Clocks(T_RC), StateIdle);
        end
        endcase
    endtask
    
    task HandleRefresh;
        UpdateCounters();
        
        // Initiate refresh when refreshCounter==0
        if (refreshCounter == 0) begin
            // Mask data lines to immediately stop reading/writing data
            sdram_dqm <= 1;
            
            // Clear our command
            sdram_cmd <= CmdNop;
            
            // Wait long to enough to guarantee we can issue CmdPrechargeAll.
            // T_RAS (row activate to precharge time) should be the most
            // conservative value, which assumes we just activated a row
            // and we have to wait before precharging it.
            NextState(Clocks(T_RAS), StateRefresh1);
        
        // Handle delays
        // This needs to come after handling refreshCounter==0, because we
        // need to ignore any delay that was happening during normal command
        // handling.
        end else if (delayCounter != 0)
            sdram_cmd <= CmdNop;
        
        // Handle Refresh states
        else case (state)
        StateRefresh1: begin
            PrechargeAll();
            // Wait T_RP (precharge to refresh/row activate) until we can issue CmdAutoRefresh
            NextState(Clocks(T_RP), StateRefresh0);
        end
        
        StateRefresh0: begin
            sdram_cmd <= CmdAutoRefresh;
            // Wait T_RC (bank activate to bank activate) to guarantee that the next command can
            // activate the same bank immediately
            NextState(Clocks(T_RC), (savedCmdTrigger ? StateHandleSaved : StateIdle));
        end
        endcase
    endtask
    
    task HandleCommand;
        UpdateCounters();
        
        // Handle delays
        if (delayCounter != 0)
            sdram_cmd <= CmdNop;
        
        // Handle commands
        else case (state)
        StateIdle: begin
            SaveCommand();
            if (cmdTrigger) PrepareReadWrite(cmdAddr);
            else sdram_cmd <= CmdNop;
        end
        
        StateHandleSaved: begin
            PrepareReadWrite(savedCmdAddr);
        end
        
        StateWrite1: begin
            HandleWrite(1);
        end
        
        StateWrite0: begin
            HandleWrite(0);
        end
        
        StateWriteAbort1: begin
            // Mask the data top stop writing immediately
            sdram_dqm <= 1;
            // Wait the 'write recover' time
            // -1 cycle because we already waited one cycle in this state.
            // Datasheet (paraphrased):
            // "The PrechargeAll command that interrupts a write burst should be
            // issued ceil(tWR/tCK) cycles after the clock edge in which the
            // last data-in element is registered."
            NextState(Clocks(T_WR)-1, StateWriteAbort0);
        end
        
        StateWriteAbort0: begin
            PrechargeAll();
            // After precharge completes, handle the saved command or go idle if there isn't a saved command
            NextState(Clocks(T_RP), (savedCmdTrigger ? StateHandleSaved : StateIdle));
        end
        
        StateRead1: begin
            HandleRead(1);
        end
        
        StateRead0: begin
            HandleRead(0);
        end
        
        StateReadAbort: begin
            // Mask the data to stop reading
            sdram_dqm <= 1;
            PrechargeAll();
            // After precharge completes, handle the saved command or go idle
            // if there isn't a saved command.
            // Wait for precharge to complete, or for the data to finish reading
            // out, whichever takes longer.
            // Use C_CAS-1 because we already spent one clock cycle of the CAS
            // latency in this state.
            NextState(Max(C_CAS-1, Clocks(T_RP)), (savedCmdTrigger ? StateHandleSaved : StateIdle));
        end
        endcase
    endtask
    
	always @(posedge clk) begin
        // Handle reset
        if (rst)
            NextStateInit(0, StateInit4);
        
        // Handle initialization
        else if (initState)
            HandleInit();
        
        // Handle refresh
        else if (refreshCounter==0 || refreshState)
            HandleRefresh();
        
        // Handle commands
        else
            HandleCommand();
    end
endmodule

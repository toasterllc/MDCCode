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
    
    task HandleWrite(input logic first);
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
            if (first) sdram_cmd <= CmdWrite;
            
            writeDataValid <= 1;
        end
        
        if (cmdTrigger) begin
            // Continue writing if we're writing to the same bank and row
            if (cmdAddrBank==savedCmdAddrBank && cmdAddrRow==savedCmdAddrRow) begin
                // Continue writing
                if (cmdWrite) NextState(0, (cmdAddrCol==savedCmdAddrCol+1 ? StateWrite0 : StateWrite1));
                
                // Transition to reading
                // TODO: should we actually wait Clocks(T_WR) before transitioning to StateRead1, to ensure the write completed? what if we're able to precharge earlier than we should after a write, by transitioning to a read before doing the precharge?
                // We don't need to wait any clock cycles before transitioning to StateRead1,
                // since we'll stop driving the DQs immediately after this state.
                // Page 11: "Input data must be removed from the DQ at least one clock cycle
                // before the Read data appears on the outputs to avoid data contention"
                else NextState(0, StateRead1);
            
            // Abort the write if we're not writing to the same bank and row
            end else NextState(0, StateWriteAbort1);
        end
    endtask
    
    task HandleRead(input logic first);
        // Save the incoming command
        SaveCommand();
        
        if (savedCmdTrigger) begin
            // Supply the column address
            sdram_a <= {3'b000, savedCmdAddrCol};
            // Unmask the data
            sdram_dqm <= 0;
            
            // Supply the read command
            if (first) sdram_cmd <= CmdRead;
            
            readDataValidShiftReg[C_CAS] <= 1;
        end
        
        if (cmdTrigger) begin
            // Continue reading if we're reading from the same bank and row
            if (cmdAddrBank==savedCmdAddrBank && cmdAddrRow==savedCmdAddrRow) begin
                // Continue reading
                if (!cmdWrite) NextState(0, (cmdAddrCol==savedCmdAddrCol+1 ? StateRead0 : StateRead1));
                
                // Transition to writing
                // Wait 3 cycles before doing so; page 8: "The DQMs must be asserted (HIGH) at
                // least two clocks prior to the Write command to suppress data-out on the DQ
                // pins. To guarantee the DQ pins against I/O contention, a single cycle with
                // high-impedance on the DQ pins must occur between the last read data and the
                // Write command (refer to the following three figures)."
                else NextState(3, StateWrite1);
            
            // Abort the read if we're not reading from the same bank and row
            end else NextState(0, StateReadAbort);
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
    
    task StartReadWrite(input logic[22:0] addr);
        // Activate the bank+row
        sdram_cmd <= CmdBankActivate;
        sdram_ba <= addr[22:21];
        sdram_a <= addr[20:9];
        
        // # Delay T_RCD or T_RAS clocks after activating the bank to perform the command.
        // - T_RCD ensures "bank activate to read/write time"
        // - T_RAS ensures "row activate to precharge time", ie that we don't
        //   CmdPrechargeAll too soon.
        // - We use Clocks(T_RAS)-2, since we know that reading/writing states take at
        //   least 2 cycles before they issue CmdPrechargeAll.
        // - If reads/writes to the same bank causes CmdBankActivate to be issued
        //   more frequently than every T_RC, then we need to add additional delay here to
        //   ensure that at least T_RC passes between CmdBankActivate commands.
        NextState(Max(Clocks(T_RCD), Clocks(T_RAS)-2), (cmdWrite ? StateWrite1 : StateRead1));
    endtask
    
    // initial $display("Max(Clocks(T_RCD), Clocks(T_RAS)-2): %d", Max(Clocks(T_RCD), Clocks(T_RAS)-2));
    // initial $finish;
    
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
            // Wait T_RC for autorefresh to complete
            // The docs say it takes TRC for AutoRefresh to complete, but T_RP must be met
            // before issuing successive AutoRefresh commands. Because TRC>T_RP, I'm
            // assuming we just have to wait TRC.
            NextStateInit(Clocks(T_RC), StateInit0);
        end
        
        StateInit0: begin
            // Autorefresh 2/2
            sdram_cmd <= CmdAutoRefresh;
            
            // Prepare refresh timer
            refreshCounter <= Max(0, Clocks(T_REFI)-1);
            
            // Wait T_RC for autorefresh to complete
            // The docs say it takes T_RC for AutoRefresh to complete, but T_RP must be met
            // before issuing successive AutoRefresh commands. Because T_RC>T_RP, I'm
            // assuming we just have to wait TRC.
            // ## Use NextState() (not NextStateInit()) because the next state isn't an
            // ## init state (StateInitXXX), and we don't want to clobber refreshCounter.
            NextState(Clocks(T_RC), StateIdle);
        end
        endcase
    endtask
    
    task HandleRefresh;
        SetDefaultState();
        
        // Initiate refresh when refreshCounter==0
        if (refreshCounter == 0)
            // Wait long to enough to guarantee we can issue CmdPrechargeAll.
            // T_RAS (row activate to precharge time) should be the most
            // conservative value, which assumes we just activated a row
            // and we have to wait before precharging it.
            NextState(Clocks(T_RAS), StateRefresh1);
        
        // Handle Refresh states
        else if (delayCounter == 0) case (state)
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
        SetDefaultState();
        
        // Handle commands
        if (delayCounter == 0) case (state)
        StateIdle: begin
            SaveCommand();
            if (cmdTrigger) StartReadWrite(cmdAddr);
        end
        
        StateHandleSaved: begin
            StartReadWrite(savedCmdAddr);
        end
        
        StateWrite1: begin
            HandleWrite(1);
        end
        
        StateWrite0: begin
            HandleWrite(0);
        end
        
        StateWriteAbort1: begin
            // Wait the 'write recover' time
            // -1 cycle because we already waited one cycle in this state.
            // Datasheet (paraphrased):
            // "The PrechargeAll command that interrupts a write burst should be
            // issued ceil(tWR/tCK) cycles after the clock edge in which the
            // last data-in element is registered."
            NextState(Max(0, Clocks(T_WR)-1), StateWriteAbort0);
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

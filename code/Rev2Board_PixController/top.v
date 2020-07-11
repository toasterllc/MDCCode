`timescale 1ps/1ps

`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

`define DO_REFRESH

module SDRAMController #(
    parameter ClockFrequency = 12000000
)(
    `define BANK_WIDTH  2
    `define ROW_WIDTH   13
    `define COL_WIDTH   10
    
    `define ADDR_WIDTH  `BANK_WIDTH+`ROW_WIDTH+`COL_WIDTH
    `define BANK_BITS   `ADDR_WIDTH-1                           -: `BANK_WIDTH
    `define ROW_BITS    `ADDR_WIDTH-`BANK_WIDTH-1               -: `ROW_WIDTH
    `define COL_BITS    `ADDR_WIDTH-`BANK_WIDTH-`ROW_WIDTH-1    -: `COL_WIDTH
    
    input wire clk,                         // Clock
    
    // Command port
    output wire cmdReady,                   // Ready for new command
    input wire cmdTrigger,                  // Start the command
    input wire cmdWrite,                    // Read (0) or write (1)
    input wire[`ADDR_WIDTH-1:0] cmdAddr,    // Address
    input wire[15:0] cmdWriteData,          // Data to write to address
    output wire[15:0] cmdReadData,          // Data read from address
    output wire cmdReadDataValid,           // `cmdReadData` is valid data
    output reg didRefresh = 0,
    
    // output reg led = 0,
    
    // RAM port
    output wire ram_clk,                    // Clock
    output reg ram_cke = 0,                 // Clock enable
    output reg[`BANK_WIDTH-1:0] ram_ba = 0, // Bank address
    output reg[`ROW_WIDTH-1:0] ram_a = 0,   // Address
    output wire ram_cs_,                    // Chip select
    output wire ram_ras_,                   // Row address strobe
    output wire ram_cas_,                   // Column address strobe
    output wire ram_we_,                    // Write enable
    output reg[1:0] ram_dqm = 0,            // Data mask
    inout wire[15:0] ram_dq                 // Data input/output
);
    // Winbond W989D6DB Timing parameters (nanoseconds)
    localparam T_INIT = 200000; // power up initialization time
    localparam T_REFI = 7812; // time between refreshes // TODO: revert back to 7812    Works:4833, Broken:4834
    localparam T_RC = 68; // bank activate to bank activate time (same bank)
    localparam T_RFC = 72; // refresh time
    localparam T_RRD = 15; // row activate to row activate time (different banks)
    localparam T_RAS = 45; // row activate to precharge time (same bank)
    localparam T_RCD = 18; // bank activate to read/write time (same bank)
    localparam T_RP = 18; // precharge to refresh/row activate (same bank)
    localparam T_WR = 15; // write recover time
    
    // // Alliance AS4C8M16SA Timing parameters (nanoseconds)
    // localparam T_INIT = 200000; // power up initialization time
    // localparam T_REFI = 15625; // time between refreshes
    // localparam T_RC = 63; // bank activate to bank activate time (same bank)
    // localparam T_RFC = 98; // refresh time // TODO: we dont know what this is for our Alliance SDRAM
    //                                         // TODO: maybe increasing this value would make Alliance SDRAM work?
    // localparam T_RRD = 14; // row activate to row activate time (different banks)
    // localparam T_RAS = 42; // row activate to precharge time (same bank)
    // localparam T_RCD = 21; // bank activate to read/write time (same bank)
    // localparam T_RP = 21; // precharge to refresh/row activate (same bank)
    // localparam T_WR = 14; // write recover time
    
    // Timing parameters (clock cycles)
    localparam C_CAS = 2; // Column address strobe (CAS) delay
    localparam C_DQZ = 2; // (T_DQZ) DQM to data high-impedance during reads delay
    localparam C_MRD = 2; // (T_MRD) set mode command to bank activate/refresh command delay
    
    // At high clock speeds, Clocks(T_RFC, 0) is the largest delay stored in delayCounter.
    // At low clock speeds, C_DQZ+1 is the largest delay stored in delayCounter.
    localparam DelayCounterWidth = Max($clog2(Clocks(T_RFC, 0)+1), $clog2(C_DQZ+1+1));
    
`ifdef SIM
    initial begin
        $display("DelayCounterWidth: %0d", DelayCounterWidth);
    end
`endif
    
    // Size refreshCounter so it'll fit Clocks(T_INIT) when combined with delayCounter
    localparam RefreshCounterWidth = $clog2(Clocks(T_INIT, 0)+1)-DelayCounterWidth;
    localparam StateWidth = 3;
    
    // initial begin
    // $display("C_DQZ+1: %0d", C_DQZ+1);
    // $display("C_MRD-1: %0d", C_MRD-1);
    // $display("Clocks(T_RFC, 0): %0d", Clocks(T_RFC, 0));
    // $display("Clocks(T_RP, 0): %0d", Clocks(T_RP, 0));
    // $display("Clocks(T_WR, 0): %0d", Clocks(T_WR, 0));
    // $display("Clocks(T_WR, 1): %0d", Clocks(T_WR, 1));
    // $display("Max(C_CAS-1, Clocks(T_RP, 0)): %0d", Max(C_CAS-1, Clocks(T_RP, 0)));
    // $display("Max(Max(Max(Clocks(T_RCD, 0), Clocks(T_RAS, 2)), Clocks(T_RC, 3)), Clocks(T_RRD, 3)): %0d", Max(Max(Max(Clocks(T_RCD, 0), Clocks(T_RAS, 2)), Clocks(T_RC, 3)), Clocks(T_RRD, 3)));
    // $display("Max(Max(Max(Max(Max(Clocks(T_RC, 1), Clocks(T_RRD, 1)), Clocks(T_RAS, 1)), Clocks(T_RCD, 1)), Clocks(T_RP, 1)), Clocks(T_WR, 1)): %0d", Max(Max(Max(Max(Max(Clocks(T_RC, 1), Clocks(T_RRD, 1)), Clocks(T_RAS, 1)), Clocks(T_RCD, 1)), Clocks(T_RP, 1)), Clocks(T_WR, 1)));
    //     // $display("DelayCounterWidth: %0d", DelayCounterWidth);
    // end
    
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
    
    function [63:0] Clocks;
        input [63:0] t;
        input [63:0] sub;
        begin
            Clocks = (t*ClockFrequency)/1000000000;
            if (Clocks >= sub) Clocks = Clocks-sub;
            else Clocks = 0;
        end
    endfunction
    
    function [63:0] Max;
        input [63:0] a;
        input [63:0] b;
        Max = (a > b ? a : b);
    endfunction
    
    reg[StateWidth-1:0] state = StateInit;
    reg[3:0] substate = 0;
    reg[DelayCounterWidth-1:0] delayCounter = 0;
    reg[RefreshCounterWidth-1:0] refreshCounter = 0;
    
    wire[DelayCounterWidth+RefreshCounterWidth-1:0] initDelayCounter = {delayCounter, refreshCounter};
    
    // cmdReady==true in the states where we invoke SaveCommand().
    // In other words, cmdReady==true when we're going to store the incoming command.
    assign cmdReady = (
        delayCounter==0 &&
`ifdef DO_REFRESH
        refreshCounter!=0 &&
`endif
        (state==StateIdle || state==StateRead || state==StateWrite));
    
    reg writeDataValid = 0;
    reg[C_CAS:0] readDataValidShiftReg = 0;
    assign cmdReadDataValid = readDataValidShiftReg[0];
    
    wire[`BANK_WIDTH-1:0] cmdAddrBank = cmdAddr[`BANK_BITS];
    wire[`ROW_WIDTH-1:0] cmdAddrRow = cmdAddr[`ROW_BITS];
    wire[`COL_WIDTH-1:0] cmdAddrCol = cmdAddr[`COL_BITS];
    
    reg savedCmdTrigger = 0;
    reg savedCmdWrite = 0;
    reg[`ADDR_WIDTH-1:0] savedCmdAddr = 0;
    reg[15:0] savedCmdWriteData = 0;
    
    wire[`BANK_WIDTH-1:0] savedCmdAddrBank = savedCmdAddr[`BANK_BITS];
    wire[`ROW_WIDTH-1:0] savedCmdAddrRow = savedCmdAddr[`ROW_BITS];
    wire[`COL_WIDTH-1:0] savedCmdAddrCol = savedCmdAddr[`COL_BITS];
    
    // ## SDRAM nets
    assign ram_clk = clk;
    assign ram_cs_ = 0;
    
    reg[2:0] ram_cmd = 0;
    assign ram_ras_ = ram_cmd[2];
    assign ram_cas_ = ram_cmd[1];
    assign ram_we_ = ram_cmd[0];
    
    reg[15:0] ram_writeData = 0;
    
    // Hook up cmdReadData/ram_writeData to ram_dq
    genvar i;
    for (i=0; i<16; i=i+1) begin
        `ifdef SIM
            // For simulation, use a normal tristate buffer
            assign ram_dq[i] = (writeDataValid ? ram_writeData[i] : 1'bz);
            assign cmdReadData[i] = ram_dq[i];
        `else
            // For synthesis, we have to use a SB_IO for a tristate buffer
            SB_IO #(
                .PIN_TYPE(6'b1010_01)
            ) dqio (
                .PACKAGE_PIN(ram_dq[i]),
                .OUTPUT_ENABLE(writeDataValid),
                .D_OUT_0(ram_writeData[i]),
                .D_IN_0(cmdReadData[i])
            );
        `endif
    end
    
    task StartState(input integer delay, input integer newState); begin
        // Verify that `delay` can fit in `delayCounter`
        `ifdef SIM
            if ($clog2(delay+1) > $bits(delayCounter)) begin
                $error("delay (%0d) is too large to fit in delayCounter (max value: %0d)", delay, {$bits(delayCounter){1'b1}});
            end
        `endif
        
        delayCounter <= delay;
        state <= newState;
        substate <= 0;
    end endtask
    
    task NextSubstate(input integer delay); begin
        `ifdef SIM
            if ($clog2(delay+1) > $bits(delayCounter)) begin
                $error("delay (%0d) is too large to fit in delayCounter (max value: %0d)", delay, {$bits(delayCounter){1'b1}});
            end
        `endif
        
        delayCounter <= delay;
        substate <= substate+1;
    end endtask
    
    task SaveCommand; begin
        // Save the command
        savedCmdTrigger <= cmdTrigger;
        // Don't clobber the previously saved command if we're not triggering,
        // so we can refer to `savedCmdAddr` to tell what address is active.
        if (cmdTrigger) begin
            savedCmdWrite <= cmdWrite;
            savedCmdAddr <= cmdAddr;
            savedCmdWriteData <= cmdWriteData;
        end
    end endtask
    
    task PrechargeAll; begin
        ram_cmd <= CmdPrechargeAll;
        ram_a <= `ROW_WIDTH'b10000000000; // ram_a[10]=1 for PrechargeAll
    end endtask
    
    task HandleWrite(input substate); begin
        // Save the incoming command
        SaveCommand();
        
        if (savedCmdTrigger) begin
            // Supply the column address
            ram_a <= savedCmdAddrCol;
            // Supply data to be written
            ram_writeData <= savedCmdWriteData;
            // Unmask the data
            ram_dqm <= 2'b00;
            
            // Supply the write command
            if (substate==0) ram_cmd <= CmdWrite;
            
            writeDataValid <= 1;
        end
        
        // Continue writing if we're writing to the same bank and row
        if (cmdTrigger && cmdAddrBank==savedCmdAddrBank && cmdAddrRow==savedCmdAddrRow) begin
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
            end else StartState(Clocks(T_WR, 1), StateRead);
        
        // Abort the write if we're not writing to the same bank and row.
        // Wait the 'write recover' time before doing so.
        // Datasheet (paraphrased):
        // "The PrechargeAll command that interrupts a write burst should be
        // issued ceil(tWR/tCK) cycles after the clock edge in which the
        // last data-in element is registered."
        end else StartState(Clocks(T_WR, 0), StateWriteAbort);
    end endtask
    
    task HandleRead(input substate); begin
        // Save the incoming command
        SaveCommand();
        
        if (savedCmdTrigger) begin
            // Supply the column address
            ram_a <= savedCmdAddrCol;
            // Unmask the data
            ram_dqm <= 2'b00;
            
            // Supply the read command
            if (substate==0) ram_cmd <= CmdRead;
            
            readDataValidShiftReg[C_CAS] <= 1;
        end
        
        // Continue reading if we're reading from the same bank and row
        if (cmdTrigger && cmdAddrBank==savedCmdAddrBank && cmdAddrRow==savedCmdAddrRow) begin
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
    end endtask
    
    task SetDefaultState; begin
        // Mask data, nop command
        ram_dqm <= 2'b11;
        ram_cmd <= CmdNop;
        
        // Update data-valid registers
        writeDataValid <= 0;
        readDataValidShiftReg <= {1'b0, readDataValidShiftReg[C_CAS:1]};
        
        // Update counters
        delayCounter <= (delayCounter!=0 ? delayCounter-1 : 0);
        refreshCounter <= (refreshCounter!=0 ? refreshCounter-1 : Clocks(T_REFI, 1));
    end endtask
    
    task StartReadWrite(input write, input[`ADDR_WIDTH-1:0] addr); begin
        // Activate the bank+row
        ram_cmd <= CmdBankActivate;
        ram_ba <= addr[`BANK_BITS];
        ram_a <= addr[`ROW_BITS];
        
        // Delay the most conservative amount of time necessary after activating the bank to perform the command.
        StartState(Max(Max(Max(
            // T_RCD: ensure "bank activate to read/write time".
            Clocks(T_RCD, 0),
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
            Clocks(T_RRD, 3)),
        (write ? StateWrite : StateRead));
    end endtask
    
    task InitSetDelayCounter(input integer delay); begin
        {delayCounter, refreshCounter} <= delay;
    end endtask
    
    task InitNextSubstate(input integer delay); begin
        InitSetDelayCounter(delay);
        substate <= substate+1;
    end endtask
    
    task HandleInit; begin
        // Handle delays
        if (initDelayCounter != 0) begin
            ram_cmd <= CmdNop;
            InitSetDelayCounter(initDelayCounter-1);
        
        // Handle init states
        end else case (substate)
            0: begin
                ram_writeData <= 0;
                savedCmdWriteData <= 0;
                ram_dqm <= 0;
                ram_cmd <= 0;
                substate <= 0;
                readDataValidShiftReg <= 0;
                delayCounter <= 0;
                refreshCounter <= 0;
                state <= StateInit;
                savedCmdAddr <= 0;
                ram_ba <= 0;
                ram_a <= 0;
                didRefresh <= 0;
                ram_cke <= 0;
                savedCmdTrigger <= 0;
                savedCmdWrite <= 0;
                writeDataValid <= 0;
                
                // Initialize registers
                ram_cke <= 0;
                ram_dqm <= 2'b11;
                ram_cmd <= CmdNop;
                // Delay 200us
                $display("init delay: %0d", Clocks(T_INIT, 0));
                InitNextSubstate(Clocks(T_INIT, 0));
            end
            
            1: begin
                // Bring ram_cke high for a bit before issuing commands
                ram_cke <= 1;
                InitNextSubstate(10);
            end
            
            2: begin
                // Precharge all banks
                PrechargeAll();
                InitNextSubstate(Clocks(T_RP, 0));
            end
            
            3: begin
                // Autorefresh 1/2
                ram_cmd <= CmdAutoRefresh;
                // Wait T_RFC for autorefresh to complete
                // The docs say it takes T_RFC for AutoRefresh to complete, but T_RP must be met
                // before issuing successive AutoRefresh commands. Because T_RFC>T_RP, assume
                // we just have to wait T_RFC.
                InitNextSubstate(Clocks(T_RFC, 0));
            end
            
            4: begin
                // Autorefresh 2/2
                ram_cmd <= CmdAutoRefresh;
                // Wait T_RFC for autorefresh to complete
                // The docs say it takes T_RFC for AutoRefresh to complete, but T_RP must be met
                // before issuing successive AutoRefresh commands. Because T_RFC>T_RP, assume
                // we just have to wait T_RFC.
                InitNextSubstate(Clocks(T_RFC, 0));
            end
            
            5: begin
                // Set the operating mode of the SDRAM
                ram_cmd <= CmdSetMode;
                // ram_ba: reserved
                ram_ba <= `BANK_WIDTH'b00;
                // ram_a:     write burst length,     test mode,  CAS latency,    burst type,     burst length
                ram_a <= {    1'b0,                   2'b0,       3'b010,         1'b0,           3'b111};
                // We need a delay of C_MRD clock cycles before issuing the next command
                // -1 clock cycle since we already burn one cycle getting to the next substate.
                InitNextSubstate(C_MRD-1);
            end
            
            6: begin
                // Set the extended operating mode of the SDRAM (applies only to Winbond RAMs)
                ram_cmd <= CmdSetMode;
                // ram_ba: reserved
                ram_ba <= `BANK_WIDTH'b10;
                // ram_a:     output drive strength,      reserved,       self refresh banks
                ram_a <= {    2'b0,                       2'b0,           3'b000};
                
                // Start the refresh timer
                refreshCounter <= Clocks(T_REFI, 1);
                
                // We need a delay of C_MRD clock cycles before issuing the next command.
                // -1 clock cycle since we already burn one cycle getting to the next substate.
                StartState(C_MRD-1, StateIdle);
            end
            endcase
    end endtask
    
    task HandleRefresh; begin
        // Initiate refresh when refreshCounter==0
        if (refreshCounter == 0) begin
            
            // We don't know what state we came from, so wait the most conservative amount of time.
            // -1 for each, because we spent a cycle in this state
            StartState(Max(Max(Max(Max(Max(
                // T_RC: the previous cycle may have issued CmdBankActivate, so prevent violating T_RC
                // when we return to that command via StateHandleSaved after refreshing is complete.
                Clocks(T_RC, 1),
                // T_RRD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RRD
                // when we return to that command via StateHandleSaved after refreshing is complete.
                Clocks(T_RRD, 1)),
                // T_RAS: the previous cycle may have issued CmdBankActivate, so prevent violating T_RAS
                // since we're about to issue CmdPrechargeAll.
                Clocks(T_RAS, 1)),
                // T_RCD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RCD
                // when we return to that command via StateHandleSaved after refreshing is complete.
                Clocks(T_RCD, 1)),
                // T_RP: the previous cycle may have issued CmdPrechargeAll, so delay other commands
                // until precharging is complete.
                Clocks(T_RP, 1)),
                // T_WR: the previous cycle may have issued CmdWrite, so delay other commands
                // until precharging is complete.
                Clocks(T_WR, 1))+1
            , StateRefresh);
            
            // if (ram_cmd != CmdNop) begin
            //     led <= 1;
            // end
            
            `ifdef SIM
                $display("ram_cmd before refresh: %0d", ram_cmd);
                // $display("DELAY MEOW: %0d %0d %0d %0d %0d %0d",
                //     // T_RC: the previous cycle may have issued CmdBankActivate, so prevent violating T_RC
                //     // when we return to that command via StateHandleSaved after refreshing is complete.
                //     Clocks(T_RC, 0),
                //     // T_RRD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RRD
                //     // when we return to that command via StateHandleSaved after refreshing is complete.
                //     Clocks(T_RRD, 0),
                //     // T_RAS: the previous cycle may have issued CmdBankActivate, so prevent violating T_RAS
                //     // since we're about to issue CmdPrechargeAll.
                //     Clocks(T_RAS, 0),
                //     // T_RCD: the previous cycle may have issued CmdBankActivate, so prevent violating T_RCD
                //     // when we return to that command via StateHandleSaved after refreshing is complete.
                //     Clocks(T_RCD, 0),
                //     // T_RP: the previous cycle may have issued CmdPrechargeAll, so delay other commands
                //     // until precharging is complete.
                //     Clocks(T_RP, 0),
                //     // T_WR: the previous cycle may have issued CmdWrite, so delay other commands
                //     // until precharging is complete.
                //     Clocks(T_WR, 0)+0
                // );
            `endif
            
        // Handle Refresh states
        end else if (delayCounter == 0) begin
            // if (!led) begin
                case (substate)
                0: begin
                    PrechargeAll();
                    // Wait T_RP (precharge to refresh/row activate) until we can issue CmdAutoRefresh
                    NextSubstate(Clocks(T_RP, 0));
                end
            
                1: begin
                    ram_cmd <= CmdAutoRefresh;
                    // Wait T_RFC (auto refresh time) to guarantee that the next command can
                    // activate the same bank immediately
                    StartState(Clocks(T_RFC, 0), (savedCmdTrigger ? StateHandleSaved : StateIdle));
                    didRefresh <= !didRefresh;
                end
                endcase
            // end
        end
    end endtask
    
    task HandleCommand; begin
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
                StartState(Clocks(T_RP, 0), (savedCmdTrigger ? StateHandleSaved : StateIdle));
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
                StartState(Max(C_CAS-1, Clocks(T_RP, 0)), (savedCmdTrigger ? StateHandleSaved : StateIdle));
            end
            endcase
        end
    end endtask
    
	always @(posedge clk) begin
        // Initialization
        if (state == StateInit)
            HandleInit();
        
        else begin
            SetDefaultState();
            
`ifdef DO_REFRESH
            // Refresh
            if (refreshCounter==0 || state==StateRefresh) HandleRefresh();
            else
`endif
            
            // Commands
            HandleCommand();
        end
    end
endmodule

module Top(
`ifndef SIM
    input wire          clk12mhz,
`endif
    output reg[3:0]     led,
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
);
    // reg[2:0] ledReg = 0;
    // assign led[2:0] = ledReg[2:0];
    
`ifdef SIM
    reg clk12mhz = 0;
`endif
    
    // ====================
    // Clock PLL (15.938 MHz)
    // ====================
    // localparam ClockFrequency = 133000000; // test for simulation
    localparam ClockFrequency = 12000000;    // fails with icestorm
    // localparam ClockFrequency = 15938000;       // works with icestorm
    wire clk = clk12mhz;
    
    
    
    
    
    // ====================
    // SDRAM controller
    // ====================
    localparam RAM_Size = 'h2000000;
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;
    
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  ram_cmdWriteData = 0;
    wire[RAM_DataWidth-1:0] ram_cmdReadData;
    wire                    ram_cmdReadDataValid;

    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),

        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(ram_cmdReadData),
        .cmdReadDataValid(ram_cmdReadDataValid),
        
        .ram_clk(ram_clk),
        .ram_cke(ram_cke),
        .ram_ba(ram_ba),
        .ram_a(ram_a),
        .ram_cs_(ram_cs_),
        .ram_ras_(ram_ras_),
        .ram_cas_(ram_cas_),
        .ram_we_(ram_we_),
        .ram_dqm(ram_dqm),
        .ram_dq(ram_dq)
    );
    
    function [15:0] DataFromAddr;
        input [24:0] addr;
        // DataFromAddr = 16'hCAFE;
        DataFromAddr = addr[15:0];
    endfunction
    
    reg[3:0] state = 0;
    reg[15:0] lastReadData = 0;
    reg[24:0] memCounter = 0;
    reg[7:0] initDelay = 0;
    always @(posedge clk) begin
        case (state)
        
        // Initialize the SDRAM
        0: begin
            initDelay <= ~0;
            state <= 1;
        end
        
        // Initialize the SDRAM
        1: begin
            if (initDelay) begin
                initDelay <= initDelay-1;
            
            end else begin
                if (!ram_cmdTrigger) begin
                    lastReadData <= 0;
                    led <= 0;
                    memCounter <= 0;
                
                    ram_cmdTrigger <= 1;
                    ram_cmdAddr <= 0;
                    ram_cmdWrite <= 1;
                    ram_cmdWriteData <= DataFromAddr(0);
                
                end else if (ram_cmdReady) begin
                    ram_cmdAddr <= ram_cmdAddr+1'b1;
                    ram_cmdWriteData <= DataFromAddr(ram_cmdAddr+1'b1);
                    
                    if (ram_cmdAddr == RAM_Size-1) begin
                        ram_cmdTrigger <= 0;
                        state <= 2;
                    end
                end
            end
        end
        
        // Start reading memory
        2: begin
            led[0] <= 1;
            ram_cmdAddr <= 0;
            ram_cmdWrite <= 0;
            ram_cmdTrigger <= 1;
            memCounter <= RAM_Size-1'b1;
            state <= 3;
        end
        
        // Continue reading memory
        3: begin
            // Handle the read being accepted
            if (ram_cmdReady && memCounter) begin
                ram_cmdAddr <= ram_cmdAddr+1'b1;
                
                // Stop triggering when we've issued all the read commands
                memCounter <= memCounter-1;
                if (memCounter == 1) begin
                    ram_cmdTrigger <= 0;
                end
            end
            
            if (ram_cmdReadDataValid) begin
                if (ram_cmdReadData && ram_cmdReadData!=(lastReadData+2'b01)) begin
                // if (ram_cmdReadData && ram_cmdReadData!=DataFromAddr(0)) begin
                    led[1] <= 1;
                    $display("BAD DATA RECEIVED");
                end
                lastReadData <= ram_cmdReadData;
            end
        end
        endcase
    end
    
`ifdef SIM
    mobile_sdr sdram(
        .clk(ram_clk),
        .cke(ram_cke),
        .addr(ram_a),
        .ba(ram_ba),
        .cs_n(ram_cs_),
        .ras_n(ram_ras_),
        .cas_n(ram_cas_),
        .we_n(ram_we_),
        .dq(ram_dq),
        .dqm(ram_dqm)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
        #800000000;
        // #10000000000;
        $finish;
    end
    
    function [63:0] CeilDiv;
        input [63:0] n;
        input [63:0] d;
        begin
            CeilDiv = (n+d-1)/d;
        end
    endfunction
    
    initial begin
        clk12mhz = 0;
        forever begin
            #(CeilDiv(1000000000000, 2*ClockFrequency));
            clk12mhz = !clk12mhz;
        end
    end
`endif
    
endmodule

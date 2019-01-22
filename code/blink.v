`timescale 1ns/1ps

// Verify constant values with yosys:
//   yosys -p "read_verilog -dump_rtlil -formal -sv blink.sv"

// Run simulation using Icarus Verilog (generates waveform file 'blink.vcd'):
//   rm -f blink.vvp ; iverilog -o blink.vvp -g2012 blink.v ; ./blink.vvp

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
    output logic sdram_ldqm,        // Data input mask
    output logic sdram_udqm,        // Data output mask
    inout logic[15:0] sdram_dq      // Data input/output
);
    
    localparam ClockFrequency = 100000000;
    localparam BurstLength = 1;
    localparam RefreshCounterWidth = $clog2(Clocks(TREFI)+1);
    
    // Timing parameters (nanoseconds)
    localparam TINIT = 200000; // power up initialization time
    localparam TREFI = 15625; // max time between refreshes
    localparam TRC = 63; // min time between activating the same bank
    localparam TRRD = 14; // min time between activating different banks
    localparam TRCD = 21; // min time between activating bank and performing read/write
    localparam TRP = 21;
    localparam TWR = 14;
    localparam CAS = 2; // Column address strobe (CAS) latency
    
    // ras_, cas_, we_
    localparam CmdPrechargeAll  = 3'b010;
    localparam CmdSetMode       = 3'b000;
    localparam CmdAutoRefresh   = 3'b001;
    localparam CmdBankActivate  = 3'b011;
    localparam CmdWrite         = 3'b100;
    localparam CmdRead          = 3'b101;
    localparam CmdNop           = 3'b111;
    
    // TODO: fix state values when we're done defining states
    localparam StateIdle                = 4'h0;
    localparam StateHandleSavedCommand  = 4'h0;
    localparam StateRestart             = 4'h1;
    localparam StateInit4               = 4'h2;
    localparam StateInit3               = 4'h3;
    localparam StateInit2               = 4'h4;
    localparam StateInit1               = 4'h5;
    localparam StateInit0               = 4'h6;
    localparam StateRefresh1            = 4'h7;
    localparam StateRefresh0            = 4'h8;
    localparam StateWrite               = 4'h9;
    localparam StateRead3               = 4'hB;
    localparam StateRead2               = 4'hC;
    localparam StateRead1               = 4'hD;
    localparam StateRead0               = 4'hE;
    
    function integer Clocks;
        // Icarus Verilog doesn't support `logic` type for arguments for some reason, so use `reg` instead.
        input reg[63:0] t;
        Clocks = (t*ClockFrequency)/1000000000;
    endfunction
    
    logic[3:0] state;
    logic[11:0] delayCounter;
    logic[RefreshCounterWidth-1:0] refreshCounter;
    
    // TODO: `cmdReady` shouldn't reflect exactly the states where we call SaveCommand
    assign cmdReady = (delayCounter==0);
    assign cmdReadDataValid = (state==StateRead0);
    
    // ## SDRAM nets
    assign sdram_clk = clk;
    assign sdram_cs_ = 0;
    
    logic[2:0] sdram_cmd;
    assign sdram_ras_ = sdram_cmd[2];
    assign sdram_cas_ = sdram_cmd[1];
    assign sdram_we_ = sdram_cmd[0];
    
    logic[1:0] cmdAddrBank;
    logic[11:0] cmdAddrRow;
    logic[8:0] cmdAddrCol;
    assign cmdAddrBank = cmdAddr[22:21];
    assign cmdAddrRow = cmdAddr[20:9];
    assign cmdAddrCol = cmdAddr[8:0];
    
    logic[3:0] saveState;
    
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
                .PULLUP(1'b0),
            ) dqio (
                .PACKAGE_PIN(sdram_dq[i]),
                // TODO: update OUTPUT_ENABLE if we have multiple Write states
                .OUTPUT_ENABLE(sdram_cmd == CmdWrite),
                .D_OUT_0(sdram_writeData[i]),
                .D_IN_0(sdram_readData[i]),
            );
        `else
            // For simulation, use a normal tristate buffer
            assign sdram_dq[i] = (sdram_cmd==CmdWrite ? sdram_writeData[i] : 1'bz);
            assign cmdReadData[i] = sdram_dq[i];
        `endif
    end
    
    // TODO: get refreshing working properly with incoming commands
    // TODO: get back-to-back reads/writes working
    // TODO: make sure we're doing the right thing with dqm
    // TODO: make sure we're adhering to tRAS.min/tRAS max -- we need to precharge the bank within a certain time
    
    task NextState(input logic[11:0] n, input logic[3:0] s);
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
    
    task PrepareReadWrite(input logic[22:0] addr);
        // TODO: we need to guarantee that TRC/TRRD are met when activating a bank
        // Activate the bank+row
        sdram_cmd <= CmdBankActivate;
        sdram_ba <= addr[22:21];
        sdram_a <= addr[20:9];
        
        // Update active address
        activeAddr <= addr;
        
        // Delay TRCD clocks after activating the bank to perform the command
        NextState(Clocks(TRCD), (cmdWrite ? StateWrite : StateRead3));
    endtask
    
	always @(posedge clk) begin
        // Handle reset
        if (rst) begin
            NextState(0, StateInit4);
        
        // Handle delays in Init states
        end else if (state>=StateInit4 && state<=StateInit0 && delayCounter>0) begin
            delayCounter <= delayCounter-1;
            sdram_cmd <= CmdNop;
        
        // Handle Init states
        end else if (state>=StateInit4 && state<=StateInit0) begin
            case (state)
            StateInit4: begin
                sdram_cke <= 0;
                sdram_dqm <= 1;
                sdram_cmd <= CmdNop;
                // Delay 200us
                NextState(Clocks(TINIT), StateInit3);
            end
            
            StateInit3: begin
                // Precharge all banks
                sdram_cke <= 1;
                sdram_cmd <= CmdPrechargeAll;
                sdram_a <= 12'b010000000000; // sdram_a[10]=1
                NextState(Clocks(TRP), StateInit2);
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
                NextState(1, StateInit1);
            end
            
            StateInit1: begin
                // Autorefresh 1/2
                sdram_cmd <= CmdAutoRefresh;
                // Wait TRC for autorefresh to complete
                // The docs say it takes TRC for AutoRefresh to complete, but TRP must be met
                // before issuing successive AutoRefresh commands. Because TRC>TRP, I'm
                // assuming we just have to wait TRC.
                NextState(Clocks(TRC), StateInit0);
            end
            
            StateInit0: begin
                // Autorefresh 2/2
                sdram_cmd <= CmdAutoRefresh;
                // Wait TRC for autorefresh to complete
                // The docs say it takes TRC for AutoRefresh to complete, but TRP must be met
                // before issuing successive AutoRefresh commands. Because TRC>TRP, I'm
                // assuming we just have to wait TRC.
                NextState(Clocks(TRC), StateIdle);
                
                // Do final set up
                sdram_dqm <= 0;
                refreshCounter <= Clocks(TREFI)-1;
            end
            endcase
        
        // Initiate refresh when refreshCounter==0
        end else if (refreshCounter == 0) begin
            // TODO: we could shorten our refresh by 1 clock cycle by starting our refresh here instead of transitioning to StateRefresh1 first
            // TODO: we need to save our current state and restore ourself to it after refresh!
            // TODO: should we save/restore `delayCounter`?
            saveState <= state;
            refreshCounter <= Clocks(TREFI)-1;
            NextState(0, StateRefresh1);
        
        // Handle delays
        end else if (delayCounter > 0) begin
            delayCounter <= delayCounter-1;
            refreshCounter <= refreshCounter-1;
            sdram_cmd <= CmdNop;
        
        // Handle Refresh states
        end else if (state>=StateRefresh1 && state<=StateRefresh0) begin
            // Update refresh counter
            refreshCounter <= refreshCounter-1;
            
            case (state)
            StateRefresh1: begin
                sdram_cmd <= CmdPrechargeAll;
                NextState(Clocks(TRP), StateRefresh0);
            end
            
            StateRefresh0: begin
                sdram_cmd <= CmdAutoRefresh;
                NextState(Clocks(TRC), (saveState==StateIdle ? StateIdle : StateRestart));
            end
            endcase
        
        // Handle command states
        end else begin
            // Update refresh counter
            refreshCounter <= refreshCounter-1;
            
            case (state)
            StateIdle: begin
                SaveCommand();
                if (cmdTrigger) PrepareReadWrite(cmdAddr);
                else sdram_cmd <= CmdNop;
            end
            
            StateHandleSavedCommand: begin
                PrepareReadWrite(savedCmdAddr);
            end
            
            StateRestart: begin
                // Restart the command that was in process before the refresh
                // TODO: we need to guarantee that TRC/TRRD are met when activating a bank
                // Activate the bank
                sdram_cmd <= CmdBankActivate;
                sdram_ba <= savedCmdAddrBank;
                sdram_a <= savedCmdAddrRow;
                
                // Delay TRCD clocks after activating the bank to perform the command
                NextState(Clocks(TRCD), (savedCmdWrite ? StateWrite : StateRead3));
            end
            
            StateWrite: begin
                SaveCommand();
                
                // Supply the column address
                sdram_a <= {3'b000, savedCmdAddrCol};
                // Supply data to be written
                sdram_writeData <= savedCmdWriteData;
                // Issue write command after activating the row, and nops after that
                sdram_cmd <= (sdram_cmd==CmdBankActivate ? CmdWrite : CmdNop);
                
                // Continue writing if we're writing to the next word
                if (cmdTrigger &&
                    cmdWrite &&
                    cmdAddrBank==activeAddrBank &&
                    cmdAddrRow==activeAddrRow &&
                    cmdAddrCol==activeAddrCol+1) begin
                    
                    // Update active address
                    activeAddr <= cmdAddr;
                
                // Otherwise complete the write by precharging
                end else begin
                    sdram_cmd <= CmdPrechargeAll;
                    NextState(Clocks(TRC), (cmdTrigger ? StateHandleSavedCommand : StateIdle));
                end
            end
            
            // StateWrite0: begin
            //     SaveCommand();
            //
            //     // Supply the column address
            //     sdram_a <= {3'b000, savedCmdAddrCol};
            //     // Supply data to be written
            //     sdram_writeData <= savedCmdWriteData;
            //     // Issue NOPs for writing sequential words
            //     sdram_cmd <= CmdNop;
            //
            //     // TODO: adhere to tRAS.max -- we cant have a row open indefinitely
            //     //       ^^^ actually our refresh interrupt will cause us to precharge all banks so we shouldn't have to do anything extra
            //
            //     // Continue writing if we're writing to the next word
            //     if (cmdTrigger &&
            //         cmdWrite &&
            //         cmdAddrBank==activeAddrBank &&
            //         cmdAddrRow==activeAddrRow &&
            //         cmdAddrCol==activeAddrCol+1) begin
            //
            //         // Update active address
            //         activeAddr <= cmdAddr;
            //
            //     // Otherwise complete the write by precharging
            //     end else begin
            //         sdram_cmd <= CmdPrechargeAll;
            //         NextState(Clocks(TRC), (cmdTrigger ? StateHandleSaved : StateIdle));
            //     end
            // end
            
            StateRead3: begin
                // Supply the column address
                sdram_a <= {3'b010, savedCmdAddrCol}; // sdram_a[10]=1 means ReadWithPrecharge
                // Issue read command
                sdram_cmd <= CmdRead;
                // Transition to NOP read state
                NextState(0, StateRead2);
            end
            
            StateRead2: begin
                // Issue NOPs after the initial read command
                sdram_cmd <= CmdNop;
                // Delay for CAS cycles before readout begins
                // -1 for the transition to this state
                // -1 for the transition to the next state
                NextState(CAS-2, StateRead1);
            end
            
            StateRead1: begin
                // Reserved state so we can sit here to meet the CAS requirement. We can't merge
                // this into StateRead0, because we can only be in StateRead0 for the exact
                // number of readout cycles, since cmdReadDataValid=(state==StateRead0).
                NextState(BurstLength-1, StateRead0);
            end
            
            StateRead0: begin
                // Wait TRP clocks before going idle (needed because we performed a Read+AutoPrecharge)
                // TODO: if Clocks(TRP)==0 can we jump from StateRead1->Idle? the problem with that though is cmdReadDataValid=(state==StateRead0)
                NextState(Clocks(TRP), StateIdle);
            end
            endcase
        end
    end
endmodule

module top();
    logic clk;
    logic delayed_clk;
    logic rst;
    
    logic cmdReady;
    logic cmdTrigger;
    logic[22:0] cmdAddr;
    logic cmdWrite;
    logic[15:0] cmdWriteData;
    logic[15:0] cmdReadData;
    logic cmdReadDataValid;
    
    logic sdram_clk;
    logic sdram_cke;
    logic[1:0] sdram_ba;
    logic[11:0] sdram_a;
    logic sdram_cs_;
    logic sdram_ras_;
    logic sdram_cas_;
    logic sdram_we_;
    logic sdram_ldqm;
    logic sdram_udqm;
    logic[15:0] sdram_dq;
    
    SDRAMController sdramController(
        .clk(delayed_clk),
        .rst(rst),
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_ldqm(sdram_ldqm),
        .sdram_udqm(sdram_udqm),
        .sdram_dq(sdram_dq)
    );
    
    task DelayClocks(input integer t);
        #(50*t);
    endtask
    
    task DelayMicroseconds(input integer t);
        #(t*1000);
    endtask
    
    initial begin
        $dumpfile("blink.vcd");
        $dumpvars(0, top);
        
        cmdTrigger = 0;
        
        // Reset
        rst = 1;
        DelayClocks(2);
        rst = 0;
        DelayClocks(1);
        
        // Wait until our RAM is ready
        wait(cmdReady) #1;
//        DelayMicroseconds(250);
        
        cmdAddr = 22'hAAAAA;
        cmdWrite = 1;
        cmdWriteData = 16'hABCD;
        DelayClocks(1);
        
        cmdTrigger = 1;
        DelayClocks(1);
        
        cmdTrigger = 0;
        DelayClocks(1);
        
        DelayClocks(100);
        
        $finish;
    end
    
    // Run clock
    initial begin
        clk = 0;
        forever begin
            #25;
            clk = !clk;
        end
    end
    
    always @(clk) begin
        #10 delayed_clk = clk;
    end
endmodule

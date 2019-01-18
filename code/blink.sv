module SDRAMController(
    input logic clk,                // Clock
    input logic rst,                // Reset (synchronous)
    
    // Command port
    output logic cmdReady,          // Ready for new command
    input logic cmdTrigger,         // Start the command
    input logic[22:0] cmdAddr,      // Address
    input logic cmdWrite,           // Read (0) or write (1)
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
    inout logic[15:0] sdram_dq,     // Data input/output
);
    
    localparam ClockFrequency = 12000000;
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
    
    localparam StateInit    = 0;
    localparam StateInit2   = 1;
    localparam StateInit3   = 2;
    localparam StateInit4   = 3;
    localparam StateInit5   = 4;
    localparam StateIdle    = 5;
    localparam StateWrite   = 6;
    localparam StateRead    = 7;
    localparam StateRead2   = 8;
    localparam StateRead3   = 9;
    localparam StateDelay   = 10;
    
    function integer Clocks;
        input logic[63:0] t;
        Clocks = (t*ClockFrequency)/1000000000;
    endfunction
    
    // Verify constant values:
    //   yosys -p "read_verilog -dump_rtlil -formal -sv blink.sv"
    
    // initial begin
    //     $display("Clocks(TREFI): %d", myvar);
    //     $display("Clocks(TREFI): %d", Clocks(TREFI));
    //     $display("Clocks(TRCD): %d", Clocks(TRCD));
    //     $display("Clocks(TRP): %d", Clocks(TRP));
    //     $display("Clocks(TWR): %d", Clocks(TWR));
    // end
    
    logic[3:0] state;
    logic[2:0] delayNextState;
    logic[11:0] delayCounter;
    logic[RefreshCounterWidth-1:0] refreshCounter;
    
    // TODO: this shouldn't reflect whether we're currently refreshing right? that should be transparent to clients?
    assign cmdReady = (state == StateIdle);
    
    // ## SDRAM nets
    
    assign sdram_clk = clk;
    assign sdram_cs_ = 0;
    
    logic[2:0] sdram_cmd;
    assign sdram_ras_ = sdram_cmd[2];
    assign sdram_cas_ = sdram_cmd[1];
    assign sdram_we_ = sdram_cmd[0];
    
    logic[1:0] cmdBankAddr = cmdAddr[22:21];
    logic[11:0] cmdRowAddr = cmdAddr[20:9];
    logic[8:0] cmdColAddr = cmdAddr[8:0];
    
    logic[22:0] saveAddr;
    logic[15:0] saveWriteData;
    
    logic[1:0] saveBankAddr = saveAddr[22:21];
    logic[11:0] saveRowAddr = saveAddr[20:9];
    logic[8:0] saveColAddr = saveAddr[8:0];
    
    logic sdram_dqm;
    assign sdram_ldqm = sdram_dqm;
    assign sdram_udqm = sdram_dqm;
    
    logic[15:0] sdram_writeData;
    logic[15:0] sdram_readData;
    
    genvar i;
    for (i=0; i<16; i=i+1) begin
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
    end
    
    // TODO: get refreshing working properly with incoming commands
    // TODO: make sure refreshing doesnt interrupt StateInit/StateInit2/StateInit3
    // TODO: make sure we're doing the right thing with dqm
    
    `define NextState(n, s)         \
        if ((n) > 0) begin          \
            state <= StateDelay;    \
            delayCounter <= (n)-1;  \
            delayNextState <= (s);  \
        end else begin              \
            state <= (s);           \
        end
    
	always_ff @(posedge clk) begin
        // Handle reset
        if (rst) begin
            state <= StateInit;
            cmdReady <= 0;
            cmdReadDataValid <= 0;
        
        end else begin
            refreshCounter <= (refreshCounter>0 ? refreshCounter-1 : 0);
            
            case (state)
            StateInit: begin
                sdram_cke <= 0;
                sdram_dqm <= 1;
                sdram_cmd <= CmdNop;
                // Delay 200us
                `NextState(Clocks(TINIT), StateInit2);
            end
            
            StateInit2: begin
                // Precharge all banks
                sdram_cke <= 1;
                sdram_cmd <= CmdPrechargeAll;
                sdram_a <= 12'b010000000000; // sdram_a[10]=1
                `NextState(Clocks(TRP), StateInit3);
            end
            
            StateInit3: begin
                // Set the operating mode of the SDRAM
                sdram_cmd <= CmdSetMode;
                // sdram_ba:    reserved
                sdram_ba <=     2'b0;
                // sdram_a:     reserved,   write burst length,     test mode,  CAS latency,    burst type,     burst length
                sdram_a <= {    2'b0,       1'b0,                   2'b0,       3'b010,         1'b0,           3'b0};
                // Delay 2 clock cycles for the mode to be set
                `NextState(2, StateInit4);
            end
            
            StateInit4: begin
                // Autorefresh 1/2
                sdram_cmd <= CmdAutoRefresh;
                // Delay TRP clocks before the next state
                `NextState(Clocks(TRP), StateInit5);
            end
            
            StateInit5: begin
                // Autorefresh 2/2
                sdram_cmd <= CmdAutoRefresh;
                // Delay TRP clocks before going Idle
                `NextState(Clocks(TRP), StateIdle);
                
                // Do final set up
                sdram_dqm <= 0;
                refreshCounter <= Clocks(TREFI)-1;
            end
            
            StateIdle: begin
                if (cmdTrigger) begin
                    // Save the address and data
                    saveAddr <= cmdAddr;
                    saveWriteData <= cmdWriteData;
                    
                    // TODO: we need to guarantee that TRC/TRRD are met when activating a bank
                    // Activate the bank
                    sdram_cmd <= CmdBankActivate;
                    sdram_ba <= cmdBankAddr;
                    sdram_a <= cmdRowAddr;
                    
                    // Delay TRCD clocks after activating the bank to perform the command
                    `NextState(Clocks(TRCD), (cmdWrite ? StateWrite : StateRead));
                end else begin
                    sdram_cmd <= CmdNop;
                end
            end
            
            StateWrite: begin
                // Supply the column address
                sdram_a <= {3'b010, saveColAddr}; // sdram_a[10]=1 means WriteWithPrecharge
                // Supply data to be written
                sdram_writeData <= saveWriteData;
                // Issue write command
                sdram_cmd <= CmdWrite;
                
                // Delay {TWR+TRP+(BurstLength-1)} clocks before going Idle
                // NOTE: need to change sleep time if we write more than 1 word! See "Write and AutoPrecharge command"..., page 11
                `NextState(Clocks(TWR+TRP)+(BurstLength-1), StateIdle);
            end
            
            StateRead: begin
                // Supply the column address
                sdram_a <= {3'b010, saveColAddr}; // sdram_a[10]=1 means ReadWithPrecharge
                // Issue read command
                sdram_cmd <= CmdRead;
                // Delay for CAS cycles before readout begins
                `NextState(CAS-1, StateRead2);
            end
            
            StateRead2: begin
                sdram_cmd <= CmdNop;
                cmdReadDataValid <= 1;
                // Wait for the data to be read out
                `NextState(BurstLength-1, StateRead3);
            end
            
            StateRead3: begin
                cmdReadDataValid <= 0;
                // Delay TRP clocks before going idle (needed because we performed a Read+AutoPrecharge)
                `NextState(Clocks(TRP), StateIdle);
            end
            
            StateDelay: begin
                sdram_cmd <= CmdNop;
                if (delayCounter == 0) state <= delayNextState;
                else delayCounter <= delayCounter-1;
            end
            endcase
        end
    end
endmodule

module clockgen(input clkin, output clkout);
	SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.PLLOUT_SELECT("GENCLK"),
		.DIVR(4'b0000),
		.DIVF(7'b1010100),
		.DIVQ(3'b110),
		.FILTER_RANGE(3'b001)
	) uut (
		.LOCK(),
		.RESETB(1'b1),
		.BYPASS(1'b0),
		.REFERENCECLK(clkin),
		.PLLOUTCORE(clkout)
	);
endmodule


module test(input logic myin, output logic myout);
    assign myout = myin;
endmodule


module main(input clk, output led1, output led2, output led3, output led4, output led5, output clkcopy, output clkout);
    logic clk;
    logic rst;
    
    logic sdram_clk;
    logic sdram_cke;
    logic[1:0] sdram_ba;
    logic[11:0] sdram_a;
    logic sdram_cs_;
    logic sdram_ras_;
    logic sdram_cas_;
    logic sdram_we_;
    logic[15:0] sdram_dq;
    
    SDRAMController sdramc(
        .clk(clk),
        .rst(rst),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_dq(sdram_dq),
    );
    
	logic[24:0] ctr;
    
    clockgen clockgen(.clkin(clk), .clkout(clkout));
    
//    logic[24:0] inlogic;
//    logic[24:0] outlogic;
//    test t(.myin(inlogic[0]), .myout(outlogic));
    
	always_ff @(posedge clkout)
		ctr <= ctr + 1;
    
	assign led1 = ctr[19];
	assign led2 = ctr[20];
	assign led3 = ctr[21];
	assign led4 = ctr[22];
	assign led5 = ctr[23];
    
    assign clkcopy = clk;
    
endmodule


//module mypll(REFERENCECLK,
//             PLLOUTCORE,
//             PLLOUTGLOBAL,
//             RESET);
//
//    input REFERENCECLK;
//    input RESET;    /* To initialize the simulation properly, the RESET signal (Active Low) must be asserted at the beginning of the simulation */ 
//    output PLLOUTCORE;
//    output PLLOUTGLOBAL;
//
//    SB_PLL40_CORE mypll_inst(.REFERENCECLK(REFERENCECLK),
//                             .PLLOUTCORE(PLLOUTCORE),
//                             .PLLOUTGLOBAL(PLLOUTGLOBAL),
//                             .EXTFEEDBACK(),
//                             .DYNAMICDELAY(),
//                             .RESETB(RESET),
//                             .BYPASS(1'b0),
//                             .LATCHINPUTVALUE(),
//                             .LOCK(),
//                             .SDI(),
//                             .SDO(),
//                             .SCLK());
//
//    //\\ Fin=12, Fout=100;
//    defparam mypll_inst.DIVR = 4'b0000;
//    defparam mypll_inst.DIVF = 7'b1000010;
//    defparam mypll_inst.DIVQ = 3'b011;
//    defparam mypll_inst.FILTER_RANGE = 3'b001;
//    defparam mypll_inst.FEEDBACK_PATH = "SIMPLE";
//    defparam mypll_inst.DELAY_ADJUSTMENT_MODE_FEEDBACK = "FIXED";
//    defparam mypll_inst.FDA_FEEDBACK = 4'b0000;
//    defparam mypll_inst.DELAY_ADJUSTMENT_MODE_RELATIVE = "FIXED";
//    defparam mypll_inst.FDA_RELATIVE = 4'b0000;
//    defparam mypll_inst.SHIFTREG_DIV_MODE = 2'b00;
//    defparam mypll_inst.PLLOUT_SELECT = "GENCLK";
//    defparam mypll_inst.ENABLE_ICEGATE = 1'b0;
//
//endmodule

//mypll mypll_inst(.REFERENCECLK(),
//                 .PLLOUTCORE(),
//                 .PLLOUTGLOBAL(),
//                 .RESET());

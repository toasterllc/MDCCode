module SDRAMController(
    input logic clk,                // Clock
    input logic rst,                // Reset (synchronous)
    
    // Command port
    input logic cmdTrigger,         // Start the command
    input logic[22:0] cmdAddr,      // Address
    input logic cmdWrite,           // Read (0) or write (1)
    input logic[15:0] cmdWriteData, // Data to write to address
    output logic[15:0] cmdReadData, // Data read from address
    output logic cmdDone,           // Previous command is complete
    
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
    
//    // SDRAM port
//    output logic sdramClk,              // Clock
//    output logic sdramClkEn,            // Clock enable
//    output logic[1:0] sdramBankAddr,    // Bank address
//    output logic[11:0] sdramAddr,       // Address
//    output logic sdramChipSel,          // Chip select
//    output logic sdramRowAddrStrobe,    // Row address strobe
//    output logic sdramColAddrStrobe,    // Column address strobe
//    output logic sdramWriteEn,          // Write enable
//    output logic sdramDataInMask,       // Data input mask
//    output logic sdramDataOutMask,      // Data output mask
//    inout logic[15:0] sdramDataInOut,   // Data input/output
);
    
    localparam ClockFrequency = 12000000;
    localparam TimeBetweenRefresh = 0.064/4096.0;
    localparam RefreshClocks = $rtoi(TimeBetweenRefresh*ClockFrequency);
    localparam RefreshCounterWidth = $clog2(RefreshClocks+1);
    
    localparam TRCD = 21e-9;
    localparam TRCDClocks = $rtoi(TRCD*ClockFrequency);
    
    localparam CmdBankActivate = 3'b011;
    
    localparam StateIdle = 0;
    localparam StateWrite = 1;
    localparam StateRead = 2;
    localparam StateDelay = 3;
    
//    initial begin
//        $display("SDRAMBankWidth: %d", SDRAMBankWidth);
//    end
    
    logic[2:0] state;
    logic[2:0] delayNextState;
    logic[3:0] delayCounter;
    
    logic[RefreshCounterWidth-1:0] refreshCounter;
    
    logic[2:0] sdram_cmd;
    assign sdram_ras_ = sdram_cmd[2];
    assign sdram_cas_ = sdram_cmd[1];
    assign sdram_we_ = sdram_cmd[0];
    
    logic[1:0] cmdBankAddr = cmdAddr[22:21];
    logic[11:0] cmdRowAddr = cmdAddr[20:9];
    logic[9:0] cmdColAddr = cmdAddr[8:0];
    
    logic[22:0] saveAddr;
    logic[22:0] saveWriteData;
    
    logic[1:0] saveBankAddr = saveAddr[22:21];
    logic[11:0] saveRowAddr = saveAddr[20:9];
    logic[9:0] saveColAddr = saveAddr[8:0];
    
	always_ff @(posedge clk) begin
        // Handle reset
        if (rst) begin
            state <= StateIdle;
            refreshCounter <= RefreshClocks;
        
        end else begin
            refreshCounter <= refreshCounter-1;
            
            case (state)
            StateIdle: begin
                // Save the address
                saveAddr <= cmdAddr;
                saveWriteData <= cmdWriteData;
                
                // Activate the bank
                sdram_cmd <= CmdBankActivate;
                sdram_ba <= cmdBankAddr;
                sdram_a <= cmdRowAddr;
                
                // Delay tRCD clocks before the next state if needed
                if (TRCDClocks > 0) begin
                    state <= StateDelay;
                    delayNextState <= (cmdWrite ? StateWrite : StateRead);
                    delayCounter <= TRCDClocks-1;
                
                // Otherwise advance to the next state without a delay
                end else begin
                    state <= (cmdWrite ? StateWrite : StateRead);
                end
            end
            
            StateWrite: begin
                sdram_a <= {2'b00, saveColAddr};
                sdram_writeData <= saveWriteData;
            end
            
            StateRead: begin
                
            end
            
            StateDelay: begin
                if (delayCounter == 0) begin
                    state <= delayNextState;
                end else begin
                    delayCounter <= delayCounter-1;
                end
            end
            
            endcase
        end
    end
    
    logic[15:0] sdram_writeData;
    logic[15:0] sdram_readData;
    
    genvar i;
    for (i=0; i<16; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1010_01),
            .PULLUP(1'b0),
        ) dqio (
            .PACKAGE_PIN(sdram_dq[i]),
            .OUTPUT_ENABLE(),
            .D_OUT_0(sdram_writeData[i]),
            .D_IN_0(sdram_readData[i]),
        );
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

// TODO: investigate whether our various toggle signals that cross clock domains are safe (such as sd_ctrl_cmdTrigger).
// currently we syncronize the toggled signal across clock domains, and assume that all dependent signals
// (sd_ctrl_cmdRespType_48, sd_ctrl_cmdRespType_136) have settled by the time the toggled signal lands in the destination
// clock domain. but if the destination clock is fast enough relative to the source clock, couldn't the destination
// clock observe the toggled signal before the dependent signals have settled?
// we should probably delay the toggle signal by 1 cycle in the source clock domain, to guarantee that all the
// dependent signals have settled in the source clock domain.

`include "ICEAppTypes.v"

`ifndef Delay_v
`define Delay_v

module Delay #(
    parameter Count = 1
)(
    input wire in,
    output wire out
);
    wire[Count:0] bits;
    assign bits[0] = in;
    assign out = bits[Count];
    genvar i;
    for (i=0; i<Count; i=i+1) begin
        SB_LUT4 #(
            .LUT_INIT(16'bxxxx_xxxx_xxxx_xx10)
        ) SB_LUT4(
            .I3(1'b0),
            .I2(1'b0),
            .I1(1'b0),
            .I0(bits[i]),
            .O(bits[i+1])
        );
    end
endmodule

`endif


`ifndef Util_v
`define Util_v

`define Var1(a)         var_``a``
`define Var2(a,b)       var_``a``_``b``
`define Var3(a,b,c)     var_``a``_``b``_``c``
`define Var4(a,b,c,d)   var_``a``_``b``_``c``_``d``

// Max: returns the larger of N values
`define Max2(a,y)           ((a) > (y) ? (a) : (y))
`define Max3(a,b,y)         (`Max2(a,b)         > (y) ? `Max2(a,b)          : (y))
`define Max4(a,b,c,y)       (`Max3(a,b,c)       > (y) ? `Max3(a,b,c)        : (y))
`define Max5(a,b,c,d,y)     (`Max4(a,b,c,d)     > (y) ? `Max4(a,b,c,d)      : (y))
`define Max6(a,b,c,d,e,y)   (`Max5(a,b,c,d,e)   > (y) ? `Max5(a,b,c,d,e)    : (y))
`define Max7(a,b,c,d,e,f,y) (`Max6(a,b,c,d,e,f) > (y) ? `Max6(a,b,c,d,e,f)  : (y))
`define Max(a,y)            `Max2(a,y)

// RegWidth: returns the width of a register to store the given values
`define RegWidth(y)                             `Max(64'b1, $clog2((y)+64'b1)) // Enforce min width of 1
`define RegWidth2(a,y)                          (`RegWidth(a)                       > `RegWidth(y) ? `RegWidth(a)                       : `RegWidth(y))
`define RegWidth3(a,b,y)                        (`RegWidth2(a,b)                    > `RegWidth(y) ? `RegWidth2(a,b)                    : `RegWidth(y))
`define RegWidth4(a,b,c,y)                      (`RegWidth3(a,b,c)                  > `RegWidth(y) ? `RegWidth3(a,b,c)                  : `RegWidth(y))
`define RegWidth5(a,b,c,d,y)                    (`RegWidth4(a,b,c,d)                > `RegWidth(y) ? `RegWidth4(a,b,c,d)                : `RegWidth(y))
`define RegWidth6(a,b,c,d,e,y)                  (`RegWidth5(a,b,c,d,e)              > `RegWidth(y) ? `RegWidth5(a,b,c,d,e)              : `RegWidth(y))
`define RegWidth7(a,b,c,d,e,f,y)                (`RegWidth6(a,b,c,d,e,f)            > `RegWidth(y) ? `RegWidth6(a,b,c,d,e,f)            : `RegWidth(y))
`define RegWidth8(a,b,c,d,e,f,g,y)              (`RegWidth7(a,b,c,d,e,f,g)          > `RegWidth(y) ? `RegWidth7(a,b,c,d,e,f,g)          : `RegWidth(y))
`define RegWidth9(a,b,c,d,e,f,g,h,y)            (`RegWidth8(a,b,c,d,e,f,g,h)        > `RegWidth(y) ? `RegWidth8(a,b,c,d,e,f,g,h)        : `RegWidth(y))
`define RegWidth10(a,b,c,d,e,f,g,h,i,y)         (`RegWidth9(a,b,c,d,e,f,g,h,i)      > `RegWidth(y) ? `RegWidth9(a,b,c,d,e,f,g,h,i)      : `RegWidth(y))
`define RegWidth11(a,b,c,d,e,f,g,h,i,j,y)       (`RegWidth10(a,b,c,d,e,f,g,h,i,j)   > `RegWidth(y) ? `RegWidth10(a,b,c,d,e,f,g,h,i,j)   : `RegWidth(y))
`define RegWidth12(a,b,c,d,e,f,g,h,i,j,k,y)     (`RegWidth11(a,b,c,d,e,f,g,h,i,j,k) > `RegWidth(y) ? `RegWidth11(a,b,c,d,e,f,g,h,i,j,k) : `RegWidth(y))

// Sub: a-b, clipping to 0
`define Sub(a,b) ((a) > (b) ? ((a)-(b)) : 0)

`define Stringify(x) `"x```"

`define Fits(container, value) ($size(container) >= `RegWidth(value))

`define LeftBit(r, idx)         r[$size(r)-(idx)-1]
`define LeftBits(r, idx, len)   r[($size(r)-(idx)-1) -: (len)]

`ifdef SIM
    `define Assert(cond) do if (!(cond)) begin $error("Assertion failed: %s (%s:%0d)", `Stringify(cond), `__FILE__, `__LINE__); $finish; end while (0)
`else
    `define Assert(cond)
`endif

`ifdef SIM
    `define Finish $finish
`else
    `define Finish
`endif

`define DivCeil(n, d) (((n)+(d)-1)/(d))

`endif


`ifndef Sync_v
`define Sync_v

// Synchronizes an async signal `in` into the clock domain `clk`
`define Sync(out, in, edge, clk)                                \
    reg out=0, `Var3(out,in,clk)=0;                             \
    always @(edge clk)                                          \
        {out, `Var3(out,in,clk)} <= {`Var3(out,in,clk), in}

`endif


`ifndef ClockGen_v
`define ClockGen_v

`timescale 1ps/1ps

module ClockGen #(
    // 100MHz by default
    parameter FREQ=100000000,
    parameter DIVR=0,
    parameter DIVF=66,
    parameter DIVQ=3,
    parameter FILTER_RANGE=1
)(
    input wire clkRef,
    output wire clk,
    output wire rst
);
    wire locked;
    wire pllClk;
    assign clk = pllClk&locked;
    
`ifdef SIM
    reg simClk;
    reg[3:0] simLockedCounter;
    assign pllClk = simClk;
    assign locked = &simLockedCounter;
    
    initial begin
        simClk = 0;
        simLockedCounter = 0;
        forever begin
            #(`DivCeil(1000000000000, 2*FREQ));
            simClk = !simClk;
            
            if (!simClk & !locked) begin
                simLockedCounter = simLockedCounter+1;
            end
        end
    end

`else
    SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(DIVR),
		.DIVF(DIVF),
		.DIVQ(DIVQ),
		.FILTER_RANGE(FILTER_RANGE)
    ) pll (
		.LOCK(locked),
		.RESETB(1'b1),
		.BYPASS(1'b0),
		.REFERENCECLK(clkRef),
		.PLLOUTCORE(pllClk)
    );
`endif
    
    // Generate `rst`
    reg init = 0;
    reg[15:0] rst_;
    assign rst = !rst_[$size(rst_)-1];
    always @(posedge clk)
        if (!init) begin
            rst_ <= 1;
            init <= 1;
        end else if (rst) begin
            rst_ <= rst_<<1;
        end
    
    // TODO: should we only output clk if locked==1? that way, if clients receive a clock, they know it's stable?
    
    // // Generate `rst`
    // reg[15:0] rstCounter;
    // always @(posedge clk)
    //     if (!locked) rstCounter <= 0;
    //     else if (rst) rstCounter <= rstCounter+1;
    // assign rst = !(&rstCounter);
endmodule

`endif




`ifndef ToggleAck_v
`define ToggleAck_v

// `out` is set (in the clock domain `clk`) when the async signal `in` toggles.
// `out` is cleared when `ack` is toggled.
`define ToggleAck(out, ack, in, edge, clk)                      \
    reg[1:0] `Var4(out,ack,in,clk) = 0;                         \
    reg ack=0;                                                  \
    wire out = (ack !== `Var4(out,ack,in,clk)[1]);              \
    always @(edge clk)                                          \
        `Var4(out,ack,in,clk) <= (`Var4(out,ack,in,clk)<<1)|in

`endif


`ifndef TogglePulse_v
`define TogglePulse_v

// Generates a single-cycle pulse on `out`, in clock domain `clk`,
// when the async signal `in` toggles.
`define TogglePulse(out, in, edge, clk)                         \
    reg[2:0] `Var3(out,in,clk) = 0;                             \
    wire out = `Var3(out,in,clk)[2]!==`Var3(out,in,clk)[1];     \
    always @(edge clk)                                          \
        `Var3(out,in,clk) <= (`Var3(out,in,clk)<<1)|in

`endif


`ifndef AFIFO_v
`define AFIFO_v

// Based on Clifford E. Cummings paper:
//   http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf
module AFIFO #(
    localparam W = 16, // Word width
    localparam N = 8   // Word count (2^N)
)(
    // Reset port (clock domain: async)
    input wire rst_,
    
    input wire w_clk,               // Write clock
    input wire w_trigger,           // Write trigger
    input wire[W-1:0] w_data,       // Write data
    output wire w_ready,            // Write OK (space available -- not full)
    
    input wire r_clk,               // Read clock
    input wire r_trigger,           // Read trigger
    output wire[W-1:0] r_data,      // Read data
    output wire r_ready             // Read OK (data available -- not empty)
);
    // ====================
    // Write handling
    // ====================
    reg[N:0] w_baddr=0, w_gaddr=0; // Write address (binary, gray)
    wire[N:0] w_baddrNext = (w_trigger&&w_ready ? w_baddr+1'b1 : w_baddr);
    wire[N:0] w_gaddrNext = (w_baddrNext>>1)^w_baddrNext;
    reg[N:0] w_rgaddr=0, w_rgaddrTmp=0;
    reg w_full = 0;
    always @(posedge w_clk, negedge rst_) begin
        if (!rst_) begin
            {w_baddr, w_gaddr} <= 0;
            {w_rgaddr, w_rgaddrTmp} <= 0;
            w_full <= 0;
        end else begin
            {w_baddr, w_gaddr} <= {w_baddrNext, w_gaddrNext};
            {w_rgaddr, w_rgaddrTmp} <= {w_rgaddrTmp, r_gaddr};
            w_full <= (w_gaddrNext === {~w_rgaddr[N:N-1], w_rgaddr[N-2:0]});
        end
    end
    
    assign w_ready = !w_full;
    
    // ====================
    // Read handling
    // ====================
    reg[N:0] r_baddr=0, r_gaddr=0; // Read addresses (binary, gray)
    wire[N:0] r_baddrNext = (r_trigger&&r_ready ? r_baddr+1'b1 : r_baddr);
    wire[N:0] r_gaddrNext = (r_baddrNext>>1)^r_baddrNext;
    reg[N:0] r_wgaddr=0, r_wgaddrTmp=0;
    reg r_empty_ = 0;
    always @(posedge r_clk, negedge rst_) begin
        if (!rst_) begin
            {r_baddr, r_gaddr} <= 0;
            {r_wgaddr, r_wgaddrTmp} <= 0;
            r_empty_ <= 0;
        end else begin
            {r_baddr, r_gaddr} <= {r_baddrNext, r_gaddrNext};
            {r_wgaddr, r_wgaddrTmp} <= {r_wgaddrTmp, w_gaddr};
            r_empty_ <= !(r_gaddrNext === r_wgaddr);
        end
    end
    
    assign r_ready = r_empty_;
    
    // ====================
    // RAM
    // ====================
    SB_RAM40_4K SB_RAM40_4K(
        .WCLK(w_clk),
        .WCLKE(1'b1),
        .WE(w_trigger && w_ready),
        .WADDR({3'b000, w_baddr[N-1:0]}),
        .WDATA(w_data),
        .MASK(16'h0000),
        
        .RCLK(r_clk),
        .RCLKE(1'b1),
        .RE(1'b1),
        .RADDR({3'b000, r_baddrNext[N-1:0]}),
        .RDATA(r_data)
    );
endmodule

`endif




`ifndef RAMController_v
`define RAMController_v

`define RAMController_Cmd_None      2'b00
`define RAMController_Cmd_Write     2'b01
`define RAMController_Cmd_Read      2'b10
`define RAMController_Cmd_Stop      2'b11

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
    
    localparam BlockSizeRegWidth    = `RegWidth(BlockSize-1),
    localparam BlockSizeCeilPow2    = 64'b1<<BlockSizeRegWidth,
    localparam BlockCount           = WordCount/BlockSizeCeilPow2,
    localparam BlockCountRegWidth   = `RegWidth(BlockCount-1)
)(
    input wire                  clk,            // Clock
    
    // TODO: consider re-ordering: cmd_block, cmd_write, cmd_trigger
    // Command port (clock domain: `clk`)
    input wire[1:0]             cmd,                // CmdWrite/CmdRead/CmdStop
    input wire[BlockCountRegWidth-1:0]  cmd_block,  // Block index
    
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
    // C_CAS: Column address strobe (CAS) delay cycles
    //   CAS=2 => Fmax=104 MHz
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
    
    // Clocks() returns the minimum number of `ClkFreq` clock cycles
    // for >= `t` nanoseconds to elapse. For example, if t=5ns, and
    // the clock period is 3ns, Clocks(t=5,sub=0) will return 2.
    // `sub` is subtracted from that value, with the result clipped to zero.
    function[63:0] Clocks;
        input[63:0] t;
        input[63:0] sub;
        begin
            Clocks = `DivCeil(t*ClkFreq, 1000000000);
            if (Clocks >= sub) Clocks = Clocks-sub;
            else Clocks = 0;
        end
    endfunction
    
    function[AddrWidth-1:0] AddrFromBlock;
        input[BlockCountRegWidth-1:0] block;
        AddrFromBlock = block << BlockSizeRegWidth;
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
    localparam Refresh_State_Count  = 6;
    localparam Refresh_State_Width  = `RegWidth(Refresh_State_Count-1);
    localparam Refresh_Delay = Clocks(T_REFI,2);    // -2 cycles:
                                                    //   -1: Because waiting N cycles requires loading a counter with N-1.
                                                    //   -1: Because Clocks() ceils the result, so if we need to
                                                    //       wait 10.5 cycles, Clocks() will return 11, when we
                                                    //       actually want 10. This can cause us to be more
                                                    //       conservative than necessary in the case where refresh period
                                                    //       is an exact multiple of the clock period, but refreshing
                                                    //       one cycle earlier is fine.
    reg[`RegWidth(Refresh_Delay)-1:0] refresh_counter = 0;
    localparam Refresh_DelayCounterWidth = `RegWidth3(
        InterruptDelay,
        Clocks(T_RP,2),
        Clocks(T_RFC,2)
    );
    reg[Refresh_DelayCounterWidth-1:0] refresh_delayCounter = 0;
    reg[Refresh_State_Width-1:0] refresh_state = 0;
    reg[Refresh_State_Width-1:0] refresh_nextState = 0;
    reg refresh_trigger = 0;
    
    
    
    localparam InterruptDelay = `Max6(
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
        Clocks(T_RCD,2)
    );
    
    localparam Data_FinishDelay = `Max4(
        // T_WR: ensure "write recover" time before precharging after a write
        // Datasheet (paraphrased):
        //   "The PrechargeAll command that interrupts a write burst should be
        //   issued ceil(tWR/tCK) cycles after the clock edge in which the
        //   last data-in element is registered."
        // -2 cycles getting to the next state
        Clocks(T_WR,2),
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
    
    localparam Data_DelayCounterWidth = `RegWidth6(
        Data_BankActivateDelay,
        Data_FinishDelay,
        Clocks(T_WR,2),
        C_CAS+1,
        Clocks(T_RP,2),
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
            ramA <= {    1'b0,                   2'b0,       C_CAS[2:0],     1'b0,           3'b111};
            
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
                    
                    refresh_delayCounter <= Clocks(T_RP,2); // -2 cycles getting to the next state
                    refresh_state <= Refresh_State_Delay;
                    refresh_nextState <= Refresh_State_Go+2;
                end
                
                Refresh_State_Go+2: begin
                    // $display("[RAM-CTRL] Refresh (time: %0d)", $time);
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
                    
                    data_delayCounter <= Clocks(T_RP,2); // -2 cycles getting to the next state
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
                // TODO: uncomment
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



`ifndef PixI2CMaster_v
`define PixI2CMaster_v

module PixI2CMaster #(
    parameter ClkFreq       = 24_000_000,   // `clk` frequency
    parameter I2CClkFreq    = 400_000       // `i2c_clk` frequency
)(
    input wire          clk,
    
    // Status port
    output reg          status_done = 0, // Toggle
    output reg          status_err = 0,
    output wire[15:0]   status_readData,
    
    // I2C port
    output wire         i2c_clk,
    inout wire          i2c_data
);
    // I2CQuarterCycleDelay: number of `clk` cycles for a quarter of the `i2c_clk` cycle to elapse.
    // DivCeil() is necessary to perform the quarter-cycle calculation, so that the
    // division is ceiled to the nearest clock cycle. (Ie -- slower than I2CClkFreq is OK, faster is not.)
    // -1 for the value that should be stored in a counter.
    localparam I2CQuarterCycleDelay = `DivCeil(ClkFreq, 4*I2CClkFreq)-1;
    
    // Width of `delay`
    localparam DelayWidth = $clog2(I2CQuarterCycleDelay+1);
    
    reg ack = 0;
    reg[7:0] dataOutShiftReg = 0;
    wire dataOut = dataOutShiftReg[7];
    reg[2:0] dataOutCounter = 0;
    reg[15:0] dataInShiftReg = 0;
    reg[3:0] dataInCounter = 0;
    assign status_readData = dataInShiftReg[15:0];
    wire dataIn;
    reg clkOut = 0;
    
    // ====================
    // i2c_clk
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b0101_01)
    ) SB_IO_i2c_clk (
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(i2c_clk),
        .D_OUT_0(clkOut)
    );
    
    // ====================
    // i2c_data
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_i2c_data (
        .INPUT_CLK(clk),
        .OUTPUT_CLK(clk),
        .PACKAGE_PIN(i2c_data),
        .OUTPUT_ENABLE(!dataOut),
        .D_OUT_0(dataOut),
        .D_IN_0(dataIn)
    );
    
    always @(posedge clk) begin
        clkOut <= 1;
        dataOutShiftReg <= ~0;
        state <= State_Idle;
    end
endmodule

`endif

`ifndef PixController_v
`define PixController_v

`define PixController_Cmd_None      2'b00
`define PixController_Cmd_Capture   2'b01
`define PixController_Cmd_Readout   2'b10

module PixController #(
    parameter ClkFreq = 24_000_000,
    parameter ImageWidthMax = 256,
    parameter ImageHeightMax = 256,
    localparam ImageSizeMax = ImageWidthMax*ImageHeightMax
)(
    input wire          clk,
    
    // Command port (clock domain: `clk`)
    input wire[1:0]     cmd,
    input wire[2:0]     cmd_ramBlock,
    
    // Readout port (clock domain: `readout_clk`)
    input wire          readout_clk,
    output wire         readout_ready,
    input wire          readout_trigger,
    output wire[15:0]   readout_data,
    
    // Status port (clock domain: `clk`)
    output reg                                  status_captureDone = 0,
    output wire[`RegWidth(ImageWidthMax)-1:0]   status_captureImageWidth,
    output wire[`RegWidth(ImageHeightMax)-1:0]  status_captureImageHeight,
    output wire[17:0]                           status_captureHighlightCount,
    output wire[17:0]                           status_captureShadowCount,
    output reg                                  status_readoutStarted = 0,
    
    // Pix port (clock domain: `pix_dclk`)
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    
    // RAM port (clock domain: `ram_clk`)
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
    // ====================
    // RAMController
    // ====================
    reg[2:0]    ramctrl_cmd_block = 0;
    reg[1:0]    ramctrl_cmd = 0;
    wire        ramctrl_write_ready;
    reg         ramctrl_write_trigger = 0;
    reg[15:0]   ramctrl_write_data = 0;
    wire        ramctrl_read_ready;
    wire        ramctrl_read_trigger;
    wire[15:0]  ramctrl_read_data;
    
    RAMController #(
        .ClkFreq(ClkFreq),
        .BlockSize(ImageSizeMax)
    ) RAMController (
        .clk(clk),
        
        .cmd(ramctrl_cmd),
        .cmd_block(ramctrl_cmd_block),
        
        .write_ready(ramctrl_write_ready),
        .write_trigger(ramctrl_write_trigger),
        .write_data(ramctrl_write_data),
        
        .read_ready(ramctrl_read_ready),
        .read_trigger(ramctrl_read_trigger),
        .read_data(ramctrl_read_data),
        
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
    
    // ====================
    // Input FIFO (Pixels->RAM)
    // ====================
    reg fifoIn_rst = 0;
    wire fifoIn_write_ready;
    wire fifoIn_write_trigger;
    wire[15:0] fifoIn_write_data;
    wire fifoIn_read_ready;
    wire fifoIn_read_trigger;
    wire[15:0] fifoIn_read_data;
    
    AFIFO AFIFO_fifoIn(
        .rst_(!fifoIn_rst),
        
        .w_clk(pix_dclk),
        .w_ready(fifoIn_write_ready),
        .w_trigger(fifoIn_write_trigger),
        .w_data(fifoIn_write_data),
        
        .r_clk(clk),
        .r_ready(fifoIn_read_ready),
        .r_trigger(fifoIn_read_trigger),
        .r_data(fifoIn_read_data)
    );
    
    // ====================
    // Output FIFO (RAM->Output)
    // ====================
    reg fifoOut_rst = 0;
    wire fifoOut_write_ready;
    wire fifoOut_write_trigger;
    wire[15:0] fifoOut_write_data;
    wire fifoOut_read_ready;
    wire fifoOut_read_trigger;
    wire[15:0] fifoOut_read_data;
    
    AFIFO AFIFO_fifoOut(
        .rst_(!fifoOut_rst),
        
        .w_clk(clk),
        .w_ready(fifoOut_write_ready),
        .w_trigger(fifoOut_write_trigger),
        .w_data(fifoOut_write_data),
        
        .r_clk(readout_clk),
        .r_ready(fifoOut_read_ready),
        .r_trigger(fifoOut_read_trigger),
        .r_data(fifoOut_read_data)
    );
    
    // ====================
    // Pin: pix_d
    // ====================
    genvar i;
    wire[11:0] pix_d_reg;
    for (i=0; i<12; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b0000_00)
        ) SB_IO_pix_d (
            .INPUT_CLK(pix_dclk),
            .PACKAGE_PIN(pix_d[i]),
            .D_IN_0(pix_d_reg[i])
        );
    end
    
    // ====================
    // Pin: pix_fv
    // ====================
    wire pix_fv_reg;
    SB_IO #(
        .PIN_TYPE(6'b0000_00)
    ) SB_IO_pix_fv (
        .INPUT_CLK(pix_dclk),
        .PACKAGE_PIN(pix_fv),
        .D_IN_0(pix_fv_reg)
    );
    
    // ====================
    // Pin: pix_lv
    // ====================
    wire pix_lv_reg;
    SB_IO #(
        .PIN_TYPE(6'b0000_00)
    ) SB_IO_pix_lv (
        .INPUT_CLK(pix_dclk),
        .PACKAGE_PIN(pix_lv),
        .D_IN_0(pix_lv_reg)
    );
    
    // ====================
    // Pixel input state machine
    // ====================
    reg fifoIn_writeEn = 0;
    
    reg ctrl_fifoInCaptureTrigger = 0;
    `TogglePulse(fifoIn_captureTrigger, ctrl_fifoInCaptureTrigger, posedge, pix_dclk);
    
    reg fifoIn_started = 0;
    `TogglePulse(ctrl_fifoInStarted, fifoIn_started, posedge, clk);
    
    reg[`RegWidth(ImageWidthMax)-1:0] fifoIn_imageWidth = 0;
    reg[`RegWidth(ImageHeightMax)-1:0] fifoIn_imageHeight = 0;
    reg[17:0] fifoIn_highlightCount = 0;
    reg[17:0] fifoIn_shadowCount = 0;
    assign status_captureImageWidth = fifoIn_imageWidth;
    assign status_captureImageHeight = fifoIn_imageHeight;
    assign status_captureHighlightCount = fifoIn_highlightCount;
    assign status_captureShadowCount = fifoIn_shadowCount;
    
    wire fifoIn_lv = pix_lv_reg;
    wire fifoIn_fv = pix_fv_reg;
    reg fifoIn_lvPrev = 0;
    reg[1:0] fifoIn_x = 0;
    reg[1:0] fifoIn_y = 0;
    
    reg fifoIn_done = 0;
    // `TogglePulse(ctrl_fifoInDone, fifoIn_done, posedge, clk);
    // `ToggleAck(ctrl_fifoInDone, ctrl_fifoInDoneAck, fifoIn_done, posedge, clk);
    `Sync(ctrl_fifoInDone, fifoIn_done, posedge, clk);
    
    reg[2:0] fifoIn_state = 0;
    always @(posedge pix_dclk) begin
        fifoIn_rst <= 0; // Pulse
        fifoIn_writeEn <= 0; // Reset by default
        fifoIn_lvPrev <= fifoIn_lv;
        
        if (fifoIn_write_trigger) begin
            // Count the width of the image
            if (!fifoIn_lvPrev) fifoIn_imageWidth <= 1;
            else                fifoIn_imageWidth <= fifoIn_imageWidth+1;
            // Count the height of the image
            if (!fifoIn_lvPrev) fifoIn_imageHeight <= fifoIn_imageHeight+1;
        end
        
        if (!fifoIn_lv) fifoIn_x <= 0;
        else            fifoIn_x <= fifoIn_x+1;
        
        if (!fifoIn_fv)                         fifoIn_y <= 0;
        else if (fifoIn_lvPrev && !fifoIn_lv)   fifoIn_y <= fifoIn_y+1;
        
        if (fifoIn_write_trigger && !fifoIn_x && !fifoIn_y) begin
            // Look at the high bits to determine if it's a highlight or shadow
            case (`LeftBits(pix_d_reg, 0, 7))
            // Highlight
            7'b1111_111:   fifoIn_highlightCount <= fifoIn_highlightCount+1;
            // Shadow
            7'b0000_000:   fifoIn_shadowCount <= fifoIn_shadowCount+1;
            endcase
        end
        
        case (fifoIn_state)
        // Idle: wait to be triggered
        0: begin
        end
        
        // Reset FIFO / ourself
        1: begin
            fifoIn_rst <= 1;
            fifoIn_done <= 0;
            fifoIn_imageWidth <= 0;
            fifoIn_imageHeight <= 0;
            fifoIn_highlightCount <= 0;
            fifoIn_shadowCount <= 0;
            fifoIn_state <= 2;
        end
        
        // Wait for FIFO to be done resetting
        2: begin
            if (!fifoIn_rst) begin
                fifoIn_started <= !fifoIn_started;
                fifoIn_state <= 3;
            end
        end
        
        // Wait for the frame to be invalid
        3: begin
            if (!pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Waiting for frame invalid...");
                fifoIn_state <= 4;
            end
        end
        
        // Wait for the frame to start
        4: begin
            if (pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Frame start");
                fifoIn_state <= 5;
            end
        end
        
        // Wait until the end of the frame
        5: begin
            fifoIn_writeEn <= 1;
            
            if (!pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Frame end");
                fifoIn_done <= 1;
                fifoIn_state <= 0;
            end
        end
        endcase
        
        if (fifoIn_captureTrigger) begin
            fifoIn_state <= 1;
        end
    end
    
    // ====================
    // Control State Machine
    // ====================
    localparam Ctrl_State_Idle      = 0; // +0
    localparam Ctrl_State_Capture   = 1; // +3
    localparam Ctrl_State_Readout   = 5; // +1
    localparam Ctrl_State_Count     = 7;
    reg[`RegWidth(Ctrl_State_Count-1)-1:0] ctrl_state = 0;
    always @(posedge clk) begin
        ramctrl_cmd <= `RAMController_Cmd_None;
        fifoOut_rst <= 0;
        status_captureDone <= 0;
        status_readoutStarted <= 0;
        ramctrl_write_trigger <= 0;
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
        end
        
        Ctrl_State_Capture: begin
            $display("[PIXCTRL:Capture] Triggered");
            // Supply 'Write' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Write;
            $display("[PIXCTRL:Capture] Waiting for RAMController to be ready to write...");
            ctrl_state <= Ctrl_State_Capture+1;
        end
        
        Ctrl_State_Capture+1: begin
            // Wait for the write command to be consumed, and for the RAMController
            // to be ready to write.
            // This is necessary because the RAMController/SDRAM takes some time to
            // initialize upon power on. If we attempted a capture during this time,
            // we'd drop most/all of the pixels because RAMController/SDRAM wouldn't
            // be ready to write yet.
            if (ramctrl_cmd===`RAMController_Cmd_None && ramctrl_write_ready) begin
                $display("[PIXCTRL:Capture] Waiting for FIFO to reset...");
                // Start the FIFO data flow now that RAMController is ready to write
                ctrl_fifoInCaptureTrigger <= !ctrl_fifoInCaptureTrigger;
                ctrl_state <= Ctrl_State_Capture+2;
            end
        end
        
        Ctrl_State_Capture+2: begin
            // Wait for the fifoIn state machine to start
            if (ctrl_fifoInStarted) begin
                ctrl_state <= Ctrl_State_Capture+3;
            end
        end
        
        Ctrl_State_Capture+3: begin
            // By default, prevent `ramctrl_write_trigger` from being reset
            ramctrl_write_trigger <= ramctrl_write_trigger;
            
            // Reset `ramctrl_write_trigger` if RAMController accepted the data
            if (ramctrl_write_ready && ramctrl_write_trigger) begin
                ramctrl_write_trigger <= 0;
            end
            
            // Copy word from FIFO->RAM
            if (fifoIn_read_ready && fifoIn_read_trigger) begin
                // $display("[PIXCTRL:Capture] Got pixel: %0d", fifoIn_read_data);
                ramctrl_write_data <= fifoIn_read_data;
                ramctrl_write_trigger <= 1;
            end
            
            // We're finished when the FIFO doesn't have data, and the fifoIn state
            // machine signals that it's done receiving data.
            if (!fifoIn_read_ready && ctrl_fifoInDone) begin
                $display("[PIXCTRL:Capture] Finished");
                status_captureDone <= 1;
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        
        Ctrl_State_Readout: begin
            $display("[PIXCTRL:Readout] Triggered");
            // Supply 'Read' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Read;
            // Reset output FIFO
            fifoOut_rst <= 1;
            ctrl_state <= Ctrl_State_Readout+1;
        end
        
        Ctrl_State_Readout+1: begin
            // Wait for the read command and FIFO reset to be consumed
            if (ramctrl_cmd===`RAMController_Cmd_None && !fifoOut_rst) begin
                status_readoutStarted <= 1;
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        endcase
        
        if (cmd !== `PixController_Cmd_None) begin
            case (cmd)
            `PixController_Cmd_Capture:     ctrl_state <= Ctrl_State_Capture;
            `PixController_Cmd_Readout:     ctrl_state <= Ctrl_State_Readout;
            endcase
        end
    end
    
    // ====================
    // Connections
    // ====================
    // Connect input FIFO write -> pixel data
    assign fifoIn_write_trigger = fifoIn_writeEn && pix_lv_reg;
    assign fifoIn_write_data = {4'b0, pix_d_reg};
    
    // Connect input FIFO read -> RAM write
    assign fifoIn_read_trigger = (!ramctrl_write_trigger || ramctrl_write_ready);
    
    // Connect RAM read -> output FIFO write
    assign fifoOut_write_trigger = ramctrl_read_ready;
    assign ramctrl_read_trigger = fifoOut_write_ready;
    assign fifoOut_write_data = ramctrl_read_data;
    
    // Connect output FIFO read -> readout port
    assign readout_ready = fifoOut_read_ready;
    assign fifoOut_read_trigger = readout_trigger;
    assign readout_data = fifoOut_read_data;
    
endmodule

`endif


`timescale 1ns/1ps

module Top(
    input wire          clk24mhz,
    
    input wire          spi_clk,
    input wire          spi_cs_,
    inout wire[7:0]     spi_d,
    
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    output reg          pix_rst_ = 0,
    output wire         pix_sclk,
    inout wire          pix_sdata,
    
    // RAM port
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
    // ====================
    // PixI2CMaster
    // ====================
    localparam PixI2CSlaveAddr = 7'h10;
    reg pixi2c_cmd_write = 0;
    reg pixi2c_cmd_dataLen = 0;
    wire pixi2c_status_done;
    wire pixi2c_status_err;
    wire[15:0] pixi2c_status_readData;
    `ToggleAck(spi_pixi2c_done_, spi_pixi2c_doneAck, pixi2c_status_done, posedge, spi_clk);
    
    PixI2CMaster #(
        .ClkFreq(24_000_000),
        .I2CClkFreq(100_000) // TODO: try 400_000 (the max frequency) to see if it works. if not, the pullup's likely too weak.
    ) PixI2CMaster (
        .clk(clk24mhz),
        
        .status_done(pixi2c_status_done), // Toggle
        .status_err(pixi2c_status_err),
        .status_readData(pixi2c_status_readData),
        
        .i2c_clk(pix_sclk),
        .i2c_data(pix_sdata)
    );
    
    
    
    
    
    
    
    // ====================
    // Pix Clock (108 MHz)
    // ====================
    localparam Pix_Clk_Freq = 108_000_000;
    wire pix_clk;
    ClockGen #(
        .FREQ(Pix_Clk_Freq),
        .DIVR(0),
        .DIVF(35),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_pix_clk(.clkRef(clk24mhz), .clk(pix_clk));
    
    // ====================
    // PixController
    // ====================
    reg[1:0]                            pixctrl_cmd = 0;
    reg[2:0]                            pixctrl_cmd_ramBlock = 0;
    wire                                pixctrl_readout_clk;
    wire                                pixctrl_readout_ready;
    wire                                pixctrl_readout_trigger;
    wire[15:0]                          pixctrl_readout_data;
    wire                                pixctrl_status_captureDone;
    wire[`RegWidth(ImageWidthMax)-1:0]  pixctrl_status_captureImageWidth;
    wire[`RegWidth(ImageHeightMax)-1:0] pixctrl_status_captureImageHeight;
    wire[17:0]                          pixctrl_status_captureHighlightCount;
    wire[17:0]                          pixctrl_status_captureShadowCount;
    wire                                pixctrl_status_readoutStarted;
    PixController #(
        .ClkFreq(Pix_Clk_Freq),
        .ImageWidthMax(ImageWidthMax),
        .ImageHeightMax(ImageHeightMax)
    ) PixController (
        .clk(pix_clk),
        
        .cmd(pixctrl_cmd),
        .cmd_ramBlock(pixctrl_cmd_ramBlock),
        
        .readout_clk(pixctrl_readout_clk),
        .readout_ready(pixctrl_readout_ready),
        .readout_trigger(pixctrl_readout_trigger),
        .readout_data(pixctrl_readout_data),
        
        .status_captureDone(pixctrl_status_captureDone),
        .status_captureImageWidth(pixctrl_status_captureImageWidth),
        .status_captureImageHeight(pixctrl_status_captureImageHeight),
        .status_captureHighlightCount(pixctrl_status_captureHighlightCount),
        .status_captureShadowCount(pixctrl_status_captureShadowCount),
        .status_readoutStarted(pixctrl_status_readoutStarted),
        
        .pix_dclk(pix_dclk),
        .pix_d(pix_d),
        .pix_fv(pix_fv),
        .pix_lv(pix_lv),
        
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
endmodule

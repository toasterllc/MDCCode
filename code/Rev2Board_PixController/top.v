`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

`include "../SDRAMController.v"

`timescale 1ps/1ps
`define DO_REFRESH

module ClockGen #(
    // 100MHz by default
    parameter FREQ=100000000,
    parameter DIVR=0,
    parameter DIVF=66,
    parameter DIVQ=3,
    parameter FILTER_RANGE=1
)(
    input wire clk12mhz,
    output wire clk,
    output wire rst
);
    wire locked;
    wire pllClk;
    assign clk = pllClk&locked;
    
    function [63:0] DivCeil;
        input [63:0] n;
        input [63:0] d;
        begin
            DivCeil = (n+d-1)/d;
        end
    endfunction
    
`ifdef SIM
    reg simClk;
    reg[3:0] simLockedCounter;
    assign pllClk = simClk;
    assign locked = &simLockedCounter;
    
    initial begin
        simClk = 0;
        simLockedCounter = 0;
        forever begin
            #(CeilDiv(1000000000000, 2*FREQ));
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
		.REFERENCECLK(clk12mhz),
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

    `ifdef SIM
        reg clk12mhz = 0;
    `endif
    
    // // ====================
    // // 1.5 MHz CLOCK START
    // // ====================
    // // localparam ClockFrequency = 133000000; // test for simulation
    // localparam ClockFrequency = 1500000;    // fails with icestorm
    // reg[2:0] clkDivider = 0;
    // wire clk = clkDivider[$size(clkDivider)-1];
    // always @(posedge clk12mhz) begin
    //     clkDivider <= clkDivider+1;
    // end
    // // ====================
    // // 1.5 MHz CLOCK END
    // // ====================
    
    // // ====================
    // // 12 MHz CLOCK START
    // // ====================
    // // localparam ClockFrequency = 133000000; // test for simulation
    // localparam ClockFrequency = 12000000;    // fails with icestorm
    // // localparam ClockFrequency = 15938000;       // works with icestorm
    // wire clk = clk12mhz;
    // // ====================
    // // 12 MHz CLOCK END
    // // ====================
    
    // ====================
    // // PLL START
    // ====================
    localparam PLLClockFrequency = 96000000;
    wire clk96mhz;
    ClockGen #(
        .FREQ(PLLClockFrequency),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk96mhz));
    
    localparam ClockFrequency = 48000000; // Frequency after clock divider
    reg[0:0] clkDivider = 0;
    wire clk = clkDivider[$size(clkDivider)-1];
    always @(posedge clk96mhz) begin
        clkDivider <= clkDivider+1;
    end
    // ====================
    // // PLL END
    // ====================
    
    
    
    
    
    // ====================
    // SDRAM controller
    // ====================
    localparam RAM_Size = 'h2000000;
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;
    // localparam RAM_EndAddr = RAM_Size-1;
    
    // localparam RAM_StartAddr = 25'h0000000;
    // localparam RAM_EndAddr =   25'h1000000;
    
    localparam RAM_StartAddr = 25'h0000000;
    localparam RAM_EndAddr =   RAM_Size-1;
    
    // localparam RAM_StartAddr = 25'h0FF00;
    // localparam RAM_EndAddr =   25'h100FF;
    
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
        // DataFromAddr = 16'hFEED;
        // DataFromAddr = 16'hCAFF;
        // DataFromAddr = 16'hCAFE;
        DataFromAddr = addr[15:0];
    endfunction
    
    reg[3:0] state = 0;
    reg[15:0] lastReadData = 0;
    reg[24:0] memCounter = 0;
    reg[7:0] initDelay = 0;
    reg lastReadDataInit = 0;
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
                    ram_cmdAddr <= RAM_StartAddr;
                    ram_cmdWrite <= 1;
                    ram_cmdWriteData <= DataFromAddr(RAM_StartAddr);
                
                end else if (ram_cmdReady) begin
                    ram_cmdAddr <= ram_cmdAddr+1'b1;
                    ram_cmdWriteData <= DataFromAddr(ram_cmdAddr+1'b1);
                    
                    // if (ram_cmdAddr == 16'h2000) begin
                    //     ram_cmdTrigger <= 0;
                    //     state <= 2;
                    //
                    //     $display("Finished writing");
                    // end
                    
                    if (ram_cmdAddr == RAM_EndAddr) begin
                        initDelay <= initDelay <= ~0;
                        ram_cmdTrigger <= 0;
                        state <= 2;
                        $display("Finished writing");
                    end
                end
            end
        end
        
        // Start reading memory
        2: begin
            if (initDelay) begin
                initDelay <= initDelay-1;
            
            end else begin
                led[0] <= 1;
                ram_cmdAddr <= RAM_StartAddr;
                ram_cmdWrite <= 0;
                ram_cmdTrigger <= 1;
                // memCounter <= 16'h1000;
                memCounter <= RAM_EndAddr-RAM_StartAddr;//-(4*16'h100);
                state <= 3;
            end
        end
        
        // Continue reading memory
        3: begin
            // Handle the read being accepted
            if (ram_cmdTrigger && ram_cmdReady) begin
                ram_cmdAddr <= ram_cmdAddr+1'b1;
                
                // Stop triggering when we've issued all the read commands
                memCounter <= memCounter-1;
                if (!memCounter) begin
// `ifdef SIM
//                     $display("Finished reading");
//                     $finish;
// `endif
                    ram_cmdTrigger <= 0;
                end
            end
            
            if (ram_cmdReadDataValid) begin
                if (lastReadDataInit && ram_cmdReadData!=(lastReadData+2'b01)) begin
                // if (lastReadDataInit && ram_cmdReadData!==DataFromAddr(0)) begin
                    led[1] <= 1;
                    $display("BAD DATA RECEIVED: wanted %x, got %x", (lastReadData+2'b01), ram_cmdReadData);
                end
                $display("GOTDATA %x, ", ram_cmdReadData);
                lastReadData <= ram_cmdReadData;
                lastReadDataInit <= 1;
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
        // #800000000;
        // #10000000000;
        // $finish;
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
            #(CeilDiv(1000000000000, 2*12000000));
            clk12mhz = !clk12mhz;
        end
    end
`endif
    
endmodule

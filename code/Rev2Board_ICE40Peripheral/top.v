`include "../Util.v"
`include "../ClockGen.v"
`include "../CRC7.v"
`include "../CRC16.v"
`include "../SDCardInitializer.v"
`include "../SDCardControllerCore.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`ifdef SIM
`include "../SDCardSim.v"
`endif

`timescale 1ns/1ps

module Top(
`ifndef SIM
    input wire          clk12mhz,
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    output reg[3:0]     led = 0
`endif
);
    
`ifdef SIM
    reg         clk12mhz = 0;
    wire        sd_clk;
    tri1        sd_cmd;
    tri1[3:0]   sd_dat;
    reg[3:0]    led = 0;
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        #200000000;
        `finish;
    end
    
    initial begin
        forever begin
            clk12mhz = 0;
            #42;
            clk12mhz = 1;
            #42;
        end
    end
    
    SDCardSim SDCardSim(
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
`endif
    
    
    
    
    
    // ====================
    // Clock PLL
    // ====================
    wire clk;
    
    // // 18 MHz
    // ClockGen #(
    //     .FREQ(18000000),
    //     .DIVR(0),
    //     .DIVF(47),
    //     .DIVQ(5),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    // // 72 MHz
    // ClockGen #(
    //     .FREQ(72000000),
    //     .DIVR(0),
    //     .DIVF(47),
    //     .DIVQ(3),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    // // 96 MHz
    // ClockGen #(
    //     .FREQ(72000000),
    //     .DIVR(0),
    //     .DIVF(63),
    //     .DIVQ(3),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    // // 120 MHz
    // ClockGen #(
    //     .FREQ(120000000),
    //     .DIVR(0),
    //     .DIVF(79),
    //     .DIVQ(3),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    // // 144 MHz
    // ClockGen #(
    //     .FREQ(144000000),
    //     .DIVR(0),
    //     .DIVF(47),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    // 168 MHz
    ClockGen #(
        .FREQ(168000000),
        .DIVR(0),
        .DIVF(55),
        .DIVQ(2),
        .FILTER_RANGE(1)
    ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    // // 174 MHz
    // ClockGen #(
    //     .FREQ(174000000),
    //     .DIVR(0),
    //     .DIVF(57),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    // // 177 MHz
    // ClockGen #(
    //     .FREQ(177000000),
    //     .DIVR(0),
    //     .DIVF(58),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    // // 180 MHz
    // ClockGen #(
    //     .FREQ(180000000),
    //     .DIVR(0),
    //     .DIVF(59),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(clk));
    
    
    
    
    
    
    
    
    // ====================
    // Registers
    // ====================
    
    wire init_done;
    wire init_err;
    wire[15:0] init_rca;
    wire init_sd_clk;
    wire init_sd_cmdIn = sd_cmdIn;
    wire init_sd_cmdOut;
    wire init_sd_cmdOutActive;
    wire[3:0] init_sd_datIn = sd_datIn;
    
    reg cmdTrigger = 0;
    
    wire[15:0] core_rca = init_rca;
    wire core_cmd_trigger = cmdTrigger && initDone[0];
    wire core_cmd_accepted;
    wire[22:0] core_cmd_writeLen = 1;
    reg[7:0] core_cmd_addr = 0;
    wire core_sd_cmdIn = sd_cmdIn;
    wire core_sd_cmdOut;
    wire core_sd_cmdOutActive;
    wire[3:0] core_sd_datIn = sd_datIn;
    wire[3:0] core_sd_datOut;
    wire core_sd_datOutActive;
    wire[15:0] core_dataOut;
    wire core_dataOut_valid;
    wire[15:0] core_dataIn = 16'h1234;
    wire core_dataIn_accepted;
    wire core_err;
    
    wire err = init_err || core_err;
    
    // Synchronize `init_done` into `clk` domain
    reg[31:0] initDone = 0;
    always @(negedge clk)
        initDone <= {init_done, 31'b0} | initDone>>1;
    
    assign sd_clk = (initDone[0] ? clk : init_sd_clk);
    
    
    
    
    
    // ====================
    // sd_cmd
    // ====================
    wire sd_cmdIn;
    wire sd_cmdOut = (initDone[0] ? core_sd_cmdOut : init_sd_cmdOut);
    wire sd_cmdOutActive = (initDone[0] ? core_sd_cmdOutActive : init_sd_cmdOutActive);
    // `ifdef SIM
    //     assign sd_cmd = (sd_cmdOutActive ? sd_cmdOut : 1'bz);
    //     assign sd_cmdIn = sd_cmd;
    // `else
        SB_IO #(
            .PIN_TYPE(6'b1101_00)
        ) SB_IO (
            .INPUT_CLK(clk),
            .OUTPUT_CLK(clk),
            .PACKAGE_PIN(sd_cmd),
            .OUTPUT_ENABLE(sd_cmdOutActive),
            .D_OUT_0(sd_cmdOut),
            .D_IN_0(sd_cmdIn)
        );
    // `endif
    
    
    
    
    // ====================
    // Pin: sd_dat
    // ====================
    wire[3:0] sd_datIn;
    wire[3:0] sd_datOut = core_sd_datOut;
    wire sd_datOutActive = core_sd_datOutActive;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        // `ifdef SIM
        //     assign sd_dat[i] = (sd_datOutActive ? sd_datOut[i] : 1'bz);
        //     assign sd_datIn[i] = sd_dat[i];
        // `else
            SB_IO #(
                .PIN_TYPE(6'b1101_00)
            ) SB_IO (
                .INPUT_CLK(clk),
                .OUTPUT_CLK(clk),
                .PACKAGE_PIN(sd_dat[i]),
                .OUTPUT_ENABLE(sd_datOutActive),
                .D_OUT_0(sd_datOut[i]),
                .D_IN_0(sd_datIn[i])
            );
        // `endif
    end

    
    
    
    
    
    
    // ====================
    // SD Card Initializer
    // ====================
    SDCardInitializer SDCardInitializer(
        .clk12mhz(clk12mhz),
        .rca(init_rca),
        .done(init_done),
        .err(init_err),
        
        .sd_clk(init_sd_clk),
        .sd_cmdIn(init_sd_cmdIn),
        .sd_cmdOut(init_sd_cmdOut),
        .sd_cmdOutActive(init_sd_cmdOutActive),
        .sd_datIn(init_sd_datIn)
    );
    
    
    
    
    
    
    
    
    
    // ====================
    // SD Card Controller Core
    // ====================
    SDCardControllerCore SDCardControllerCore(
        .clk(clk),
        .rca(core_rca),
        
        // Command port
        .cmd_trigger(core_cmd_trigger),
        .cmd_accepted(core_cmd_accepted),
        .cmd_writeLen(core_cmd_writeLen),
        .cmd_addr(32'b0|core_cmd_addr),
        
        // Data-out port
        .dataOut(core_dataOut),
        .dataOut_valid(core_dataOut_valid),
        
        // Data-in port
        .dataIn(core_dataIn),
        .dataIn_accepted(core_dataIn_accepted),
        
        .err(core_err),
        
        .sd_cmdIn(core_sd_cmdIn),
        .sd_cmdOut(core_sd_cmdOut),
        .sd_cmdOutActive(core_sd_cmdOutActive),
        .sd_datIn(core_sd_datIn),
        .sd_datOut(core_sd_datOut),
        .sd_datOutActive(core_sd_datOutActive)
    );
    
    // ====================
    // State Machine
    // ====================
    reg[1:0] state = 0;
    
    // Read a single block
    always @(posedge clk) begin
        case (state)
        0: begin
            led <= 0;
            cmdTrigger <= 0;
            core_cmd_addr <= 0;
            state <= 1;
        end
        
        1: begin
            led[0] <= 1;
            cmdTrigger <= 1;
            if (core_cmd_accepted) begin
                $display("[SD HOST] Write accepted");
                state <= 2;
            end
        end
        
        2: begin
            cmdTrigger <= 0;
            if (core_cmd_accepted) begin
                $display("[SD HOST] Stop accepted");
                state <= 3;
            end
        end
        
        3: begin
            led[1] <= 1;
        end
        endcase
        
        
        if (initDone[0]) led[2] <= 1;
        if (err) led[3] <= 1;
    end
    
endmodule

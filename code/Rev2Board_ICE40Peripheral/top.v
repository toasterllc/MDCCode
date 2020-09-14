`include "../Util.v"
`include "../ClockGen.v"
`include "../CRC7.v"
`include "../CRC16.v"
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
    input wire          sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    output reg[3:0]     led = 0
`endif
);
    
`ifdef SIM
    reg         sd_clk;
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
            sd_clk = 0;
            #42;
            sd_clk = 1;
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
    // State Machine Registers
    // ====================
    reg sd_cmd_trigger = 0;
    wire sd_cmd_accepted;
    reg sd_cmd_write = 0;
    wire[22:0] sd_cmd_writeLen = 1;
    reg[7:0] sd_cmd_addr = 0;
    wire[15:0] sd_dataOut;
    wire sd_dataOut_valid;
    wire[15:0] sd_dataIn = 16'h1234;
    wire sd_dataIn_accepted;
    wire sd_err;
    
    
    
    
    // ====================
    // sd_cmd
    // ====================
    wire sd_cmdIn;
    wire sd_cmdOut;
    wire sd_cmdOutActive;
    `ifdef SIM
        assign sd_cmd = (sd_cmdOutActive ? sd_cmdOut : 1'bz);
        assign sd_cmdIn = sd_cmd;
    `else
        SB_IO #(
                .PIN_TYPE(6'b1101_00)
        ) SB_IO (
            .INPUT_CLK(sd_clk),
            .OUTPUT_CLK(sd_clk),
            .PACKAGE_PIN(sd_cmd),
            .OUTPUT_ENABLE(sd_cmdOutActive),
            .D_OUT_0(sd_cmdOut),
            .D_IN_0(sd_cmdIn)
        );
    `endif
    
    
    
    
    // ====================
    // Pin: sd_dat
    // ====================
    wire[3:0] sd_datIn;
    wire[3:0] sd_datOut;
    wire sd_datOutActive;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        `ifdef SIM
            assign sd_dat[i] = (sd_datOutActive ? sd_datOut[i] : 1'bz);
            assign sd_datIn[i] = sd_dat[i];
        `else
            SB_IO #(
                .PIN_TYPE(6'b1101_00)
            ) SB_IO (
                .INPUT_CLK(sd_clk),
                .OUTPUT_CLK(sd_clk),
                .PACKAGE_PIN(sd_dat[i]),
                .OUTPUT_ENABLE(sd_datOutActive),
                .D_OUT_0(sd_datOut[i]),
                .D_IN_0(sd_datIn[i])
            );
        `endif
    end

    
    
    
    // ====================
    // SD Card Controller Core
    // ====================
    SDCardControllerCore SDCardControllerCore(
        .clk(sd_clk),
        .rca(16'hAAAA),
        
        // Command port
        .cmd_trigger(sd_cmd_trigger),
        .cmd_accepted(sd_cmd_accepted),
        .cmd_write(sd_cmd_write),
        .cmd_writeLen(sd_cmd_writeLen),
        .cmd_addr(32'b0|sd_cmd_addr),
        
        // Data-out port
        .dataOut(sd_dataOut),
        .dataOut_valid(sd_dataOut_valid),
        
        // Data-in port
        .dataIn(sd_dataIn),
        .dataIn_accepted(sd_dataIn_accepted),
        
        .err(sd_err),
        
        .sd_cmdIn(sd_cmdIn),
        .sd_cmdOut(sd_cmdOut),
        .sd_cmdOutActive(sd_cmdOutActive),
        .sd_datIn(sd_datIn),
        .sd_datOut(sd_datOut),
        .sd_datOutActive(sd_datOutActive)
    );
    
    // ====================
    // State Machine
    // ====================
    reg[2:0] state = 0;
    
    // Read a single block
    always @(posedge sd_clk) begin
        case (state)
        0: begin
            // led <= 0;
            sd_cmd_trigger <= 0;
            sd_cmd_write <= 0;
            sd_cmd_addr <= 0;
            state <= 1;
        end
        
        1: begin
            sd_cmd_trigger <= 1;
            sd_cmd_write <= 0;
            if (sd_cmd_accepted) begin
                $display("[SD HOST] Read accepted");
                state <= 2;
            end
        end
        
        2: begin
            sd_cmd_trigger <= 0;
            if (sd_cmd_accepted) begin
                $display("[SD HOST] Stop accepted");
            end
        end
        endcase

        // if (sd_dataOut_valid) begin
        //     $display("[SD HOST] Got read data: %h", sd_dataOut);
        //     led[0] <= 1;
        //
        //     if (sd_dataOut === sd_dataIn) begin
        //         led[1] <= 1;
        //     end
        //
        //     if (sd_dataOut !== sd_dataIn) begin
        //         led[2] <= 1;
        //     end
        // end

        // if (idone) led[3] <= 1;
        // if (err) led[3] <= 1;
    end
    
    
    
endmodule

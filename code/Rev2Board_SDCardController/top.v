`include "../Util.v"
`include "../ClockGen.v"
`include "../CRC7.v"
`include "../CRC16.v"
`include "../SDCardController.v"
`include "../SDCardControllerCore.v"
`include "../SDCardInitializer.v"

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
        #100000000;
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
    // SD Card Controller
    // ====================
    reg sd_cmd_trigger = 0;
    reg sd_cmd_write = 0;
    reg[22:0] sd_cmd_writeLen = 0;
    reg[7:0] sd_cmd_addr = 0;
    wire[15:0] sd_dataOut;
    wire sd_dataOut_valid;
    reg[15:0] sd_dataIn = 16'hFFFF;
    wire sd_dataIn_accepted;
    wire err;
    
    SDCardController SDCardController(
        .clk12mhz(clk12mhz),
        .clk(clk), // FIXME: remove once we have our own clock and SDCardController has its CDC logic in place
        
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
        
        .err(err),
        
        // SD port
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    // ====================
    // State Machine
    // ====================
    reg[3:0] state = 0;
    
    // Toggle between reading/writing blocks
    always @(posedge clk) begin
        case (state)
        0: begin
            sd_cmd_trigger <= 1;
            if (sd_cmd_accepted) begin
                if (sd_cmd_write) begin
                    $display("[SD HOST] Write accepted");
                end else begin
                    $display("[SD HOST] Read accepted");
                end
                state <= 1;
            end
        end
        
        1: begin
            sd_cmd_trigger <= 0;
            if (sd_cmd_accepted) begin
                $display("[SD HOST] Stop accepted");
                sd_cmd_write <= !sd_cmd_write;
                state <= 0;
            end
        end
        endcase
        
        if (sd_dataOut_valid) begin
            $display("[SD HOST] Got read data: %h", sd_dataOut);
            led <= sd_dataOut;
        end
    end
    
    // // Read 2 blocks, write 2 blocks
    // always @(posedge clk) begin
    //     case (state)
    //     0: begin
    //         sd_cmd_trigger <= 1;
    //         // sd_cmd_len <= 2;
    //         sd_cmd_write <= 0;
    //         // Wait until read is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Read accepted");
    //             state <= 1;
    //         end
    //     end
    //
    //     1: begin
    //         // Wait until read is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Read accepted (#2)");
    //             state <= 2;
    //         end
    //     end
    //
    //     2: begin
    //         sd_cmd_trigger <= 0;
    //         // Wait until stop is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Stop accepted");
    //             state <= 3;
    //         end
    //     end
    //
    //     3: begin
    //         // Write 1 block
    //         sd_cmd_trigger <= 1;
    //         sd_cmd_write <= 1;
    //         // Wait until write is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Write accepted");
    //             state <= 4;
    //         end
    //     end
    //
    //     4: begin
    //         if (sd_dataIn_accepted) begin
    //             sd_dataIn <= ~sd_dataIn;
    //         end
    //
    //         // Wait until write is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Write accepted (#2)");
    //             state <= 5;
    //         end
    //     end
    //
    //     5: begin
    //         if (sd_dataIn_accepted) begin
    //             sd_dataIn <= ~sd_dataIn;
    //         end
    //
    //         // Stop writing
    //         sd_cmd_trigger <= 0;
    //         // Wait until stop is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Stop accepted");
    //             $display("[SD HOST] DONE ✅");
    //             state <= 6;
    //         end
    //     end
    //
    //     6: begin
    //     end
    //     endcase
    //
    //     if (sd_dataOut_valid) begin
    //         $display("[SD HOST] Got read data: %h", sd_dataOut);
    //         led <= sd_dataOut;
    //     end
    // end
endmodule

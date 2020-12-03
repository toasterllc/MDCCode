`timescale 1ns/1ps

`include "Util.v"
`include "Delay.v"

// ====================
// SPI Messages/Responses
// ====================
`define Msg_Len                                                 64

`define Msg_Type_Len                                            8
`define Msg_Type_Bits                                           63:56

`define Msg_Arg_Len                                             56
`define Msg_Arg_Bits                                            55:0

`define Resp_Len                                                `Msg_Len
`define Resp_Arg_Bits                                           63:0

`define Msg_Type_Echo                                           `Msg_Type_Len'h00
`define     Msg_Arg_Echo_Msg_Len                                56
`define     Msg_Arg_Echo_Msg_Bits                               55:0
`define     Resp_Arg_Echo_Msg_Bits                              63:8

`define Msg_Type_ReadData                                       `Msg_Type_Len'h01

`define Msg_Type_NoOp                                           `Msg_Type_Len'hFF

module Top(
    input wire      clk24mhz,
    input wire      spi_clk,
    input wire      spi_cs_,
    inout wire[7:0] spi_d,
    
    output reg[3:0] led = 0
);
    wire spi_clk_int;
    Delay #(
        .Count(0)
    ) Delay (
        .in(spi_clk),
        .out(spi_clk_int)
    );
    
    // ====================
    // Pin: spi_cs_
    // ====================
    wire spi_cs_tmp_;
    wire spi_cs = !spi_cs_tmp_;
    SB_IO #(
        .PIN_TYPE(6'b0000_01),
        .PULLUP(1'b1)
    ) SB_IO_spi_cs (
        .PACKAGE_PIN(spi_cs_),
        .D_IN_0(spi_cs_tmp_)
    );
    
    // ====================
    // Pin: spi_d
    // ====================
    genvar i;
    reg spi_d_outEn = 0;
    wire[7:0] spi_d_out;
    wire[7:0] spi_d_in;
    for (i=0; i<8; i++) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_00),
            .PULLUP(1'b1)
        ) SB_IO_sd_cmd (
            .INPUT_CLK(spi_clk_int),
            .OUTPUT_CLK(spi_clk_int),
            .PACKAGE_PIN(spi_d[i]),
            .OUTPUT_ENABLE(spi_d_outEn),
            .D_OUT_0(spi_d_out[i]),
            .D_IN_0(spi_d_in[i])
        );
    end
    
    
    // ====================
    // SPI State Machine
    // ====================
    
    // MsgCycleCount notes:
    //
    //   - We include a dummy byte at the beginning of each command, to workaround an
    //     apparent STM32 bug that always sends the first nibble as 0xF. As such, we
    //     need to add 2 cycles to `MsgCycleCount`. Without this dummy byte,
    //     MsgCycleCount=(`Msg_Len/4)-1, so with this dummy byte,
    //     MsgCycleCount=(`Msg_Len/4)+1.
    //
    //   - Commands use 4 lines (spi_d[3:0]), so we divide `Msg_Len by 4.
    //
    localparam MsgCycleCount = (`Msg_Len/4)+1;
    reg[2:0] spi_state = 0;
    reg[`RegWidth(MsgCycleCount)-1:0] spi_dinCounter = 0;
    reg[0:0] spi_doutCounter = 0;
    reg[`Msg_Len-1:0] spi_dinReg = 0;
    reg[15:0] spi_doutReg = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    reg[15:0] spi_doutDataCounter = 0;
    wire[`Msg_Type_Len-1:0] spi_msgType = spi_dinReg[`Msg_Type_Bits];
    wire[`Msg_Arg_Len-1:0] spi_msgArg = spi_dinReg[`Msg_Arg_Bits];
    
    assign spi_d_out = {
        `LeftBits(spi_doutReg, 8, 4),   // High 4 bits: 4 bits of byte 1
        `LeftBits(spi_doutReg, 0, 4)    // Low 4 bits:  4 bits of byte 0
    };
    
    always @(posedge spi_clk_int, negedge spi_cs) begin
        // Reset ourself when we're de-selected
        if (!spi_cs) begin
            spi_state <= 0;
            spi_d_outEn <= 0;
        
        end else begin
            // Commands only use 4 lines (spi_d[3:0]) because it's quadspi.
            spi_dinReg <= spi_dinReg<<4|spi_d_in[3:0];
            spi_dinCounter <= spi_dinCounter-1;
            spi_doutReg <= spi_doutReg<<4|4'hF;
            spi_doutCounter <= spi_doutCounter-1;
            spi_d_outEn <= 0;
            spi_resp <= spi_resp<<8|8'hFF;
            
            case (spi_state)
            0: begin
                spi_dinCounter <= MsgCycleCount;
                spi_state <= 1;
            end
            
            1: begin
                if (!spi_dinCounter) begin
                    spi_state <= 2;
                end
            end
            
            2: begin
                // // spi_resp <= 64'h123456789ABCDEF0;
                // spi_resp <= spi_dinReg;
                // spi_doutCounter <= 0;
                // spi_state <= 3;
                
                // By default, return to state 0
                spi_state <= 0;
                spi_doutCounter <= 0;

                case (spi_msgType)
                // Echo
                `Msg_Type_Echo: begin
                    $display("[SPI] Got Msg_Type_Echo: %0h", spi_msgArg[`Msg_Arg_Echo_Msg_Bits]);
                    spi_resp[`Resp_Arg_Echo_Msg_Bits] <= spi_msgArg[`Msg_Arg_Echo_Msg_Bits];
                    spi_state <= 3;
                end

                // ReadData
                `Msg_Type_ReadData: begin
                    spi_state <= 4;
                end

                // NoOp
                `Msg_Type_NoOp: begin
                    $display("[SPI] Got Msg_Type_None");
                end

                default: begin
                    $display("[SPI] BAD COMMAND: %0h ❌", spi_msgType);
                    `Finish;
                end
                endcase
            end

            3: begin
                spi_d_outEn <= 1;
                if (!spi_doutCounter) begin
                    spi_doutReg <= `LeftBits(spi_resp, 0, 16);
                end
            end
            
            4: begin
                spi_d_outEn <= 1;
                if (!spi_doutCounter) begin
                    // spi_doutReg <= 16'h3742;
                    spi_doutReg <= spi_doutDataCounter;
                    spi_doutDataCounter <= spi_doutDataCounter+1;
                end
            end
            endcase
        end
    end
endmodule







`ifdef SIM
module Testbench();
    reg clk24mhz = 0;
    wire[3:0] led;
    
    reg         spi_clk = 0;
    reg         spi_cs_ = 0;
    wire[7:0]   spi_d;
    wire[7:0]   spi_d_out;
    reg         spi_d_outEn = 0;    
    wire[7:0]   spi_d_in;
    assign spi_d = (spi_d_outEn ? spi_d_out : {8{1'bz}});
    assign spi_d_in = spi_d;
    
    reg[`Msg_Len-1:0] spi_doutReg = 0;
    reg[15:0] spi_dinReg = 0;
    reg[`Resp_Len-1:0] resp = 0;
    assign spi_d_out[7:4] = `LeftBits(spi_doutReg,0,4);
    assign spi_d_out[3:0] = `LeftBits(spi_doutReg,0,4);
    
    Top Top(.*);
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
    
    initial begin
        forever begin
            clk24mhz = 0;
            #21;
            clk24mhz = 1;
            #21;
        end
    end
    
    localparam SPI_CLK_HALF_PERIOD = 21;
    
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg, input[31:0] respLen); begin
        reg[15:0] i;
        
        spi_cs_ = 0;
        spi_doutReg = {typ, arg};
        spi_d_outEn = 1;
            
            // 2 initial dummy cycles
            for (i=0; i<2; i++) begin
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 1;
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 0;
            end
            
            for (i=0; i<`Msg_Len/4; i++) begin
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 1;
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 0;
                
                spi_doutReg = spi_doutReg<<4|{4{1'b1}};
            end
            
            spi_d_outEn = 0;
            
            // Dummy cycles
            for (i=0; i<4; i++) begin
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 1;
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 0;
            end
            
            // Clock in response
            for (i=0; i<respLen; i++) begin
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 1;
                
                    if (!i[0]) spi_dinReg = 0;
                    spi_dinReg = spi_dinReg<<4|{4'b0000, spi_d_in[3:0], 4'b0000, spi_d_in[7:4]};
                    
                    resp = resp<<8;
                    if (i[0]) resp = resp|spi_dinReg;
                
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 0;
            end
        
        spi_cs_ = 1;
        #1; // Allow spi_cs_ to take effect
    end endtask
    
    task TestNoOp; begin
        $display("\n========== TestNoOp ==========");
        SendMsg(`Msg_Type_NoOp, 56'h123456789ABCDE, 8);
        if (resp === 64'hFFFFFFFFFFFFFFFF) begin
            $display("Response OK: %h ✅", resp);
        end else begin
            $display("Bad response: %h ❌", resp);
            `Finish;
        end
    end endtask
    
    task TestEcho; begin
        reg[`Msg_Arg_Echo_Msg_Len-1:0] arg;
        $display("\n========== TestEcho ==========");
        arg = `Msg_Arg_Echo_Msg_Len'h123456789ABCDE;
        
        SendMsg(`Msg_Type_Echo, arg, 8);
        if (resp[`Resp_Arg_Echo_Msg_Bits] === arg) begin
            $display("Response OK: %h ✅", resp[`Resp_Arg_Echo_Msg_Bits]);
        end else begin
            $display("Bad response: %h ❌", resp[`Resp_Arg_Echo_Msg_Bits]);
            `Finish;
        end
    end endtask

    task TestReadData; begin
        $display("\n========== TestReadData ==========");
        SendMsg(`Msg_Type_ReadData, 0, 8);
        $display("Response: %h", resp);
    end endtask
    
    initial begin
        reg[15:0] i, ii;
        reg done;
        
        // Set our initial state
        spi_cs_ = 1;
        spi_doutReg = ~0;
        spi_d_outEn = 0;
        
        // Pulse the clock to get SB_IO initialized
        spi_clk = 1;
        #1;
        spi_clk = 0;
        
        // TestNoOp();
        TestEcho();
        TestReadData();
        TestReadData();
        
        `Finish;
    end
endmodule
`endif

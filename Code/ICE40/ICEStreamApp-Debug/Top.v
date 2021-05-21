// TODO: investigate whether our various toggle signals that cross clock domains are safe (such as sd_ctrl_cmdTrigger).
// currently we syncronize the toggled signal across clock domains, and assume that all dependent signals
// (sd_ctrl_cmdRespType_48, sd_ctrl_cmdRespType_136) have settled by the time the toggled signal lands in the destination
// clock domain. but if the destination clock is fast enough relative to the source clock, couldn't the destination
// clock observe the toggled signal before the dependent signals have settled?
// we should probably delay the toggle signal by 1 cycle in the source clock domain, to guarantee that all the
// dependent signals have settled in the source clock domain.

`include "ICEAppTypes.v"


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



`ifndef RAMController_v
`define RAMController_v

`define RAMController_Cmd_None      2'b00
`define RAMController_Cmd_Write     2'b01
`define RAMController_Cmd_Read      2'b10
`define RAMController_Cmd_Stop      2'b11

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
    
    // Status port (clock domain: `clk`)
    output wire[`RegWidth(ImageWidthMax)-1:0]   status_captureImageWidth,
    output wire[`RegWidth(ImageHeightMax)-1:0]  status_captureImageHeight,
    output reg                                  status_readoutStarted = 0,
    
    // Pix port (clock domain: `pix_dclk`)
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    
    output wire[12:0]   ram_a,
);
    reg[2:0]    ramctrl_cmd_block = 0;
    reg[1:0]    ramctrl_cmd = 0;
    wire        ramctrl_write_ready;
    reg         ramctrl_write_trigger = 0;
    reg[15:0]   ramctrl_write_data = 0;
    wire        ramctrl_read_ready;
    wire        ramctrl_read_trigger;
    wire[15:0]  ramctrl_read_data;
    
    // ====================
    // Input FIFO (Pixels->RAM)
    // ====================
    wire fifoIn_read_ready = 1'b1;
    wire[15:0] fifoIn_read_data = {4'b0, pix_d_reg};
    
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
    
    assign ram_a[11:0] = pix_d_reg[11:0];
    
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
    assign status_captureImageWidth = fifoIn_imageWidth;
    assign status_captureImageHeight = fifoIn_imageHeight;
    
    wire fifoIn_lv = pix_lv_reg;
    wire fifoIn_fv = pix_fv_reg;
    reg fifoIn_lvPrev = 0;
    reg[1:0] fifoIn_x = 0;
    reg[1:0] fifoIn_y = 0;
    
    reg fifoIn_done = 0;
    
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
        status_readoutStarted <= 0;
        ramctrl_write_trigger <= 0;
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
            ctrl_state <= Ctrl_State_Capture;
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
            // By default, prevent `ramctrl_write_trigger` from being reset
            ramctrl_write_trigger <= ramctrl_write_trigger;
            
            // Reset `ramctrl_write_trigger` if RAMController accepted the data
            if (ramctrl_write_ready && ramctrl_write_trigger) begin
                ramctrl_write_trigger <= 0;
            end
            
            // Copy word from FIFO->RAM
            if (fifoIn_read_ready && fifoIn_read_trigger) begin
                ramctrl_write_data <= fifoIn_read_data;
                ramctrl_write_trigger <= 1;
            end
            
            // We're finished when the FIFO doesn't have data, and the fifoIn state
            // machine signals that it's done receiving data.
            if (!fifoIn_read_ready && ctrl_fifoInDone) begin
                $display("[PIXCTRL:Capture] Finished");
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        endcase
    end
    
    // ====================
    // Connections
    // ====================
    
    // Connect input FIFO read -> RAM write
    assign fifoIn_read_trigger = (!ramctrl_write_trigger || ramctrl_write_ready);
    
    // Connect RAM read -> output FIFO write
    assign fifoOut_write_trigger = ramctrl_read_ready;
    assign ramctrl_read_trigger = fifoOut_write_ready;
    assign fifoOut_write_data = ramctrl_read_data;
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
    
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
);
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_i2c_data (
        .INPUT_CLK(clk24mhz),
        .OUTPUT_CLK(clk24mhz),
        .PACKAGE_PIN(pix_sdata),
        .OUTPUT_ENABLE(0),
        .D_OUT_0(),
        .D_IN_0()
    );
    
    // ====================
    // PixController
    // ====================
    wire[`RegWidth(ImageWidthMax)-1:0]  pixctrl_status_captureImageWidth;
    wire[`RegWidth(ImageHeightMax)-1:0] pixctrl_status_captureImageHeight;
    wire                                pixctrl_status_readoutStarted;
    PixController PixController (
        .clk(clk24mhz),
        
        .status_captureImageWidth(pixctrl_status_captureImageWidth),
        .status_captureImageHeight(pixctrl_status_captureImageHeight),
        .status_readoutStarted(pixctrl_status_readoutStarted),
        
        .pix_dclk(pix_dclk),
        .pix_d(pix_d),
        .pix_fv(pix_fv),
        .pix_lv(pix_lv),
        
        .ram_a(ram_a),
    );
endmodule

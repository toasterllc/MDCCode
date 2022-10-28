`ifndef Pin_v
`define Pin_v

`define Pin_Mode_PushPull    1'b0
`define Pin_Mode_OpenDrain   1'b1
`define Pin_Mode_Width       1

module PinOut #(
    parameter Reg = 0,
    parameter Pullup = 0
)(
    input wire clk,     // if Reg=1
    input wire[`Pin_Mode_Width-1:0]
               mode,
    input wire out,
    output wire pin
);
    
    generate if (Reg) begin
        // TODO: implement
    
    end else begin
        wire douten  = (mode===`Pin_Mode_PushPull ? 1'b1 : ~out);
        wire dout    = (mode===`Pin_Mode_PushPull ? out  : 1'b0);
        
        SB_IO #(
            .PIN_TYPE(6'b1010_01),
            .PULLUP(Pullup)
        ) SB_IO (
            .INPUT_CLK      (),
            .OUTPUT_CLK     (),
            .PACKAGE_PIN    (pin),
            .OUTPUT_ENABLE  (douten),
            .D_OUT_0        (dout),
            .D_OUT_1        (),
            .D_IN_0         (),
            .D_IN_1         ()
        );
    end endgenerate
    
endmodule




module PinInOut #(
    parameter Reg = 0,
    parameter Pullup = 0
)(
    input wire clk,     // if Reg=1
    input wire[`Pin_Mode_Width-1:0]
               mode,
    input wire dir,     // in=0, out=1
    input wire out,
    output wire in,
    inout wire pin
);
    
    generate if (Reg) begin
        wire douten  = (dir ? (mode===`Pin_Mode_PushPull ? 1'b1 : ~out) : 1'b0);
        wire dout    = (mode===`Pin_Mode_PushPull ? out  : 1'b0);
        
        SB_IO #(
            .PIN_TYPE(6'b1101_00),
            .PULLUP(Pullup)
        ) SB_IO (
            .INPUT_CLK      (clk),
            .OUTPUT_CLK     (clk),
            .PACKAGE_PIN    (pin),
            .OUTPUT_ENABLE  (douten),
            .D_OUT_0        (dout),
            .D_OUT_1        (),
            .D_IN_0         (in),
            .D_IN_1         ()
        );
    
    end else begin
        // TODO: implement
    end endgenerate
    
endmodule






// `define IO_Dir_Out      0
// `define IO_Dir_InOut    1
//
// `define IO_Mode_Out     0
// `define IO_Mode_InOut   1
//
// module IO #(
//     parameter Dir = ,
// )(
//     input wire in,
//     input wire mode,
//     output wire out
// );
//     wire[Count:0] bits;
//     assign bits[0] = in;
//     assign out = bits[Count];
//     genvar i;
//     for (i=0; i<Count; i=i+1) begin
//         SB_LUT4 #(
//             .LUT_INIT(16'bxxxx_xxxx_xxxx_xx10)
//         ) SB_LUT4(
//             .I3(1'b0),
//             .I2(1'b0),
//             .I1(1'b0),
//             .I0(bits[i]),
//             .O(bits[i+1])
//         );
//     end
// endmodule

`endif

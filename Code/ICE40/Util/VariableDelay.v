`ifndef VariableDelay_v
`define VariableDelay_v

`timescale 1ns/1ps

// // One-hot `sel`
// module VariableDelay #(
//     parameter Count = 1
// )(
//     input wire in,
//     input wire[Count-1:0] sel,
//     output wire out
// );
//     wire[Count-1:0] bits;
//     assign bits[0] = in;
//     genvar i;
//     for (i=0; i<Count-1; i=i+1) begin
//         wire #(1) dbits = bits[i];
//         SB_LUT4 #(
//             .LUT_INIT(16'bxxxx_xxxx_xxxx_xx10)
//         ) SB_LUT4(
//             .I3(1'b0),
//             .I2(1'b0),
//             .I1(1'b0),
//             .I0(dbits),
//             .O(bits[i+1])
//         );
//     end
//
//     for (i=0; i<Count; i=i+1) begin
//         assign out = (sel[i] ? bits[i] : 1'bz);
//     end
// endmodule



// Binary `sel`
module VariableDelay #(
    parameter Count = 1,
    localparam SelWidth = $clog2(Count)
)(
    input wire in,
    input wire[SelWidth-1:0] sel,
    output wire out
);
    wire[Count-1:0] bits;
    assign bits[0] = in;
    genvar i;
    for (i=0; i<Count-1; i=i+1) begin
        wire #(1) dbits = bits[i];
        // Buffers
        SB_LUT4 #(
            .LUT_INIT(16'bxxxx_xxxx_xxxx_xx10)
        ) SB_LUT4(
            .I3(1'b0),
            .I2(1'b0),
            .I1(1'b0),
            .I0(dbits),
            .O(bits[i+1])
        );
        
        // // Inverters
        // SB_LUT4 #(
        //     .LUT_INIT(16'bxxxx_xxxx_xxxx_xx01)
        // ) SB_LUT4(
        //     .I3(1'b0),
        //     .I2(1'b0),
        //     .I1(1'b0),
        //     .I0(dbits),
        //     .O(bits[i+1])
        // );
    end
    
    assign out = bits[sel];
endmodule

`endif

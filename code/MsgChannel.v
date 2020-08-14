// // MsgChannel
// //   Transmits a single-clock pulse across clock domains.
// //   Pulses can be dropped if they occur more rapidly than they can be acknowledged.
// module MsgChannel #(
//     parameter MsgLen = 8
// )(
//     input wire              in_clk,
//     input wire              in_trigger,
//     input wire[MsgLen-1:0]  in_msg,
//
//     input wire              out_clk,
//     output reg              out_trigger = 0,
//     output reg[MsgLen-1:0]  out_msg = 0
// );
//     reg in_req = 0;
//     reg in_ack = 0;
//     wire in_idle = !in_req & !in_ack;
//     always @(posedge in_clk)
//         if (in_idle & in_trigger) begin
//             in_req <= 1;
//             out_msg <= in_msg; // Synchronization is handled by our trigger-synchronization logic
//
//         end else if (in_ack)
//             in_req <= 0;
//
//     reg out_req=0, out_req2=0;
//     reg tmp1 = 0;
//     always @(posedge out_clk) begin
//         { out_req2, out_req, tmp1 } <= { out_req, tmp1, in_req };
//         out_trigger <= (!out_req2 & out_req);
//     end
//
//     reg tmp2 = 0;
//     always @(posedge in_clk)
//         { in_ack, tmp2 } <= { tmp2, out_req2 };
// endmodule








// MsgChannel
//   Transmits a message+trigger signal across clock domains.
//   Messages are dropped if they're sent faster than they can be consumed.
module MsgChannel #(
    parameter MsgLen = 8
)(
    input wire              in_clk,
    input wire              in_trigger,
    input wire[MsgLen-1:0]  in_msg,

    input wire              out_clk,
    output wire             out_trigger,
    output reg[MsgLen-1:0]  out_msg = 0
);
    reg in_req = 0;
    reg in_ack = 0;
    wire in_idle = !in_req & !in_ack;
    always @(posedge in_clk)
        if (in_idle & in_trigger) begin
            in_req <= 1;
            out_msg <= in_msg; // Synchronization is handled by our trigger-synchronization logic

        end else if (in_ack)
            in_req <= 0;

    reg out_req=0, out_req2=0;
    reg tmp1 = 0;
    always @(posedge out_clk)
        { out_req2, out_req, tmp1 } <= { out_req, tmp1, in_req };

    reg tmp2 = 0;
    always @(posedge in_clk)
        { in_ack, tmp2 } <= { tmp2, out_req };

    assign out_trigger = !out_req2 & out_req; // Trigger pulse occurs upon the positive edge of `out_req`.
endmodule

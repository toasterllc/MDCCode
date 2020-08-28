`include "../SDCardController.v"

`timescale 1ns/1ps

module Adder #(
    parameter N = 4
)(
    input wire[N-1:0] a,
    input wire[N-1:0] b,
    input wire cin,
    output wire[N-1:0] sum,
    output wire cout
);
    wire[N:0] s = a+b+cin;
    assign sum = s[N-1:0];
    assign cout = s[N];
endmodule

// module Adder4(
//     input wire[3:0] a,
//     input wire[3:0] b,
//     input wire cin,
//     output wire[3:0] sum,
//     output wire cout
// );
//     wire[4:0] s = a+b+cin;
//     assign sum = s[3:0];
//     assign cout = s[4];
// endmodule

module ShiftAdder #(
    parameter W = 16,
    parameter N = 4
)(
    input wire clk,
    input wire load_,
    input wire[W-1:0] a,
    input wire[W-1:0] b,
    output reg[W-1:0] sum = 0,
    output wire done
);
    reg[W/N:0] doneReg = 0;
    reg[W-1:0] aReg = 0;
    reg[W-1:0] bReg = 0;
    reg cin = 0;
    
    wire[N:0] s = aReg[N-1:0] + bReg[N-1:0] + cin;
    wire[N-1:0] sumPart = s[N-1:0];
    wire cout = s[N];
    
    assign done = doneReg[W/N];
    always @(posedge clk) begin
        if (!load_) begin
            doneReg <= 1;
            aReg <= a;
            bReg <= b;
            cin <= 0;
        
        end else begin
            doneReg <= doneReg<<1;
            aReg <= aReg>>N;
            bReg <= bReg>>N;
            cin <= cout;
            sum <= {sumPart, sum[W-1:N]};
        end
    end
endmodule


module Top(
`ifndef SIM
    input wire          clk12mhz,
`endif
    input wire[15:0]    a,
    output wire[15:0]   out,
    
    output reg test = 0
);
`ifdef SIM
    reg clk12mhz = 0;
`endif
    localparam W = 32;
    localparam N = 4;
    
    reg load_ = 0;
    wire done;
    reg[W-1:0] acum = 0;
    wire[W-1:0] sum;
    assign out = acum[W-1 : W-16-1];
    ShiftAdder #(
        .W(W),
        .N(N)
    ) adder(
        .clk(clk12mhz),
        .load_(load_),
        .a(acum),
        .b(a),
        .sum(sum),
        .done(done)
    );

    always @(posedge clk12mhz) begin
        if (!load_) load_ <= 1;
        else if (done) begin
            load_ <= 0;
            acum <= sum;
        end
        $display("acum: %b", acum);
    end

    
    
    // reg[W-1:0] acum = 0;
    // assign out = acum[W-1 : W-16-1];
    // always @(posedge clk12mhz) begin
    //     acum <= acum+a;
    //     $display("acum: %b", acum);
    // end
    
    
    
    
    // reg[15:0] a = 16'b1111_1111_1111_1111;
    // reg[15:0] b = 1;
    //
    // wire[3:0] s0;
    // wire c0out;
    // reg c0 = 0;
    // Adder4 adder0(
    //     .a(a[3:0]),
    //     .b(b[3:0]),
    //     .cin(1'b0),
    //     .sum(s0),
    //     .cout(c0out)
    // );
    //
    // wire[3:0] s1;
    // wire c1out;
    // reg c1 = 0;
    // Adder4 adder1(
    //     .a(a[7:4]),
    //     .b(b[7:4]),
    //     .cin(c0),
    //     .sum(s1),
    //     .cout(c1out)
    // );
    //
    // wire[3:0] s2;
    // wire c2out;
    // reg c2 = 0;
    // Adder4 adder2(
    //     .a(a[11:8]),
    //     .b(b[11:8]),
    //     .cin(c1),
    //     .sum(s2),
    //     .cout(c2out)
    // );
    //
    // wire[3:0] s3;
    // reg c3 = 0;
    // Adder4 adder3(
    //     .a(a[15:12]),
    //     .b(b[15:12]),
    //     .cin(c2),
    //     .sum(s3),
    //     .cout()
    // );
    //
    // reg[3:0] tracker = 0;
    //
    // always @(posedge clk12mhz) begin
    //     c0 <= c0out;
    //     c1 <= c1out;
    //     c2 <= c2out;
    //
    //     tracker <= tracker<<1;
    //     if (!tracker) begin
    //         tracker <= 1;
    //
    //     end else if (tracker[3]) begin
    //         tracker <= 1;
    //         a <= {s3, s2, s1, s0};
    //         if (!{s3, s2, s1, s0}) led <= led+1;
    //         $display("%b", {s3, s2, s1, s0});
    //     end
    // end
    
    
    // reg[15:0] shiftReg = 0;
    // reg[3:0] counter = 0;
    // reg init = 0;
    // always @(posedge clk12mhz) begin
    //     if (!init || shiftReg[15]) begin
    //         init <= 1;
    //         shiftReg <= 16'b1;
    //         led <= led+1;
    //         counter <= counter-1;
    //     end else begin
    //         shiftReg <= shiftReg<<1;
    //     end
    //
    //     if (!counter) led <= led+1;
    // end
    
    
    
    
    
    // reg[255:0] shiftReg = 0;
    // reg init = 0;
    // always @(posedge clk12mhz) begin
    //     if (!init || shiftReg[255]) begin
    //         init <= 1;
    //         shiftReg <= 256'b1;
    //         led <= led+1;
    //     end else begin
    //         shiftReg <= shiftReg<<1;
    //     end
    // end
    
    
    
    
    
    // always @(posedge clk12mhz) begin
    //     tmp <= tmp+a;
    // end
    
    
    
    
`ifdef SIM
    // assign a = 16'b1111_1111_1111_1111;
    assign a = 16'b0000_0000_0000_0001;
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        forever begin
            clk12mhz = 0;
            #42;
            clk12mhz = 1;
            #42;
        end
    end
    
    // initial begin
    //     #10000;
    //     $finish;
    // end
`endif
endmodule

`timescale 1ns/1ps

module MyModule();
    parameter MyParam = 1;
    localparam MyParamLocal = 1;
endmodule


module Top(
    input wire clk24mhz,
    output wire dout1,
    output wire dout2,
);
    MyModule MyModule();
    
    assign dout1 = MyModule.MyParam;
    assign dout2 = MyModule.MyParamLocal;
    
    assign dout1 = AAA.MyParam;
    assign dout2 = AAA.MyParamLocal;
    
    // assign dout = 0;
endmodule

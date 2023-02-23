`include "Util.v"

`timescale 1ns/1ps

`define Img_TestHeader  '{                                      \
    8'hEE, 8'hFF, 8'hC0,                                        \ /* magic number        */
    8'h00,                                                      \ /* version             */
    8'h00, 8'h09,                                               \ /* image width         */
    8'h10, 8'h05,                                               \ /* image height        */
    8'h11, 8'h11,                                               \ /* coarse int time     */
    8'h22, 8'h22,                                               \ /* analog gain         */
    8'hA0, 8'hA1, 8'hA2, 8'hA3, 8'hA4, 8'hA5, 8'hA6, 8'hA7,     \ /* id                  */
    8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6, 8'hB7,     \ /* timestamp           */
    8'h00, 8'h00, 8'h00, 8'h00                                  \ /* padding             */
}


module Testbench();
    task Config(
        input reg[15:0] header
    ); begin
        $display("[PixelValidator] hello %x", header);
    end endtask
    
    reg[7:0] arr[] = `Img_TestHeader;
    initial begin
        reg[15:0] a;
        $display("AAA");
        a = { arr[0], arr[1] };
        Config(a);
        $finish;
    end
endmodule










// `include "Util.v"

//
// `timescale 1ns/1ps
//
// `define Img_TestHeader  '{                                      \
//     8'hEE, 8'hFF, 8'hC0,                                        \ /* magic number        */
//     8'h00,                                                      \ /* version             */
//     8'h00, 8'h09,                                               \ /* image width         */
//     8'h10, 8'h05,                                               \ /* image height        */
//     8'h11, 8'h11,                                               \ /* coarse int time     */
//     8'h22, 8'h22,                                               \ /* analog gain         */
//     8'hA0, 8'hA1, 8'hA2, 8'hA3, 8'hA4, 8'hA5, 8'hA6, 8'hA7,     \ /* id                  */
//     8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6, 8'hB7,     \ /* timestamp           */
//     8'h00, 8'h00, 8'h00, 8'h00                                  \ /* padding             */
// }
//
//
// module Testbench #(
//     parameter W = 16 // Word width; allowed values: 16, 8, 4, 2
// )();
//
//     reg[7:0] _cfgHeader[];
//
//     task Config(
//         input reg[7:0] header[]
//     ); begin
//         $display("[PixelValidator] hello header.size:%0d %x %x %x %x %x %x", header.size, header[0], header[1], header[2], header[3], header[4], header[5]);
//         _cfgHeader = header;
//     end endtask
//
//     reg[7:0] arr[];
//     initial begin
//         Config(`Img_TestHeader);
//         $finish;
//     end
// endmodule

`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../uart.v"

module Top(
    input wire          clk12mhz,
    
    output reg[7:0]     led = 0,
    
    input wire          uart_rx,
    output wire         uart_tx
);
    // 24 MHz clock
    localparam ClockFrequency =   24000000;
    wire clk;
    wire rst;
    ClockGen #(
        .FREQ(ClockFrequency),
		.DIVR(0),
		.DIVF(63),
		.DIVQ(5),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst(rst));
    
    // UART stuff
    reg uartTransmit = 0;
    reg [7:0] uartTxByte = 0;
    wire uartReceived;
    wire [7:0] uartRxByte;
    wire uartTransmitting;
    
    uart #(
        .baud_rate(9600),                   // The baud rate in kilobits/s
        .sys_clk_freq(ClockFrequency)       // The master clock frequency
    )
    uart0(
        .clk(clk),                          // The master clock for this module
        .rst(rst),                          // Synchronous reset
        .rx(uart_rx),                       // Incoming serial line
        .tx(uart_tx),                       // Outgoing serial line
        .transmit(uartTransmit),            // Signal to transmit
        .tx_byte(uartTxByte),               // Byte to transmit
        .received(uartReceived),            // Indicated that a byte has been received
        .rx_byte(uartRxByte),               // Byte received
        .is_receiving(),                    // Low when receive line is idle
        .is_transmitting(uartTransmitting), // Low when transmit line is idle
        .recv_error()                       // Indicates error in receiving packet.
    );
    
    always @(posedge clk) begin
        // Reset uartTransmit
        uartTransmit <= 0;
        
        // Wait until active transmissions complete
        if (uartReceived & !uartTransmitting) begin
            uartTxByte <= uartRxByte;
            uartTransmit <= 1;
            led <= uartRxByte;
        end
    end
endmodule

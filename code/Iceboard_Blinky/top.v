`timescale 1ns/1ps

module Top(
    input wire         clk12mhz,
    output wire        ledRed
);
    wire clk = clk12mhz;
    
    // Generate our own reset signal
    // This relies on the fact that the ice40 FPGA resets flipflops to 0 at power up
    reg[12:0] rstCounter;
    reg rst;
    reg lastBit;
    assign rst = !rstCounter[$size(rstCounter)-1];
    always @(posedge clk) begin
        if (rst) begin
            rstCounter <= rstCounter+1;
        end
    end
	
	reg[24:0] counter;
    always @(posedge clk) begin
		if (rst) begin
			counter <= 0;
		end else begin
			counter <= counter+1;
		end
    end
	
	assign ledRed = counter[$size(counter)-1];
    
    `ifdef SIM
    initial rstCounter = 0;
    `endif
endmodule

`ifdef SIM

module Iceboard_BlinkySim(
    output wire        ledRed
);

    wire clk12mhz;

    Iceboard_Blinky icestickSDRAMTest(
        .clk12mhz(clk12mhz),
        .ledRed(ledRed)
    );

    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Iceboard_BlinkySim);

        #10000000;
        $finish;
    end

    initial begin
        clk12mhz = 0;
        forever begin
            clk12mhz = !clk12mhz;
            #42;
        end
    end
endmodule

`endif

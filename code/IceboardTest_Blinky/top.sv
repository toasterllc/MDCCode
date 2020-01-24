`define SIM
`timescale 1ns/1ps

module IceboardTest_Blinky(
    input logic         clk12mhz,
    output logic        ledRed
);
    logic clk;
    assign clk = clk12mhz;
    
    // Generate our own reset signal
    // This relies on the fact that the ice40 FPGA resets flipflops to 0 at power up
    logic[12:0] rstCounter;
    logic rst;
    logic lastBit;
    assign rst = !rstCounter[$size(rstCounter)-1];
    always @(posedge clk) begin
        if (rst) begin
            rstCounter <= rstCounter+1;
        end
    end
	
	logic[24:0] counter;
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

module IceboardTest_BlinkySim(
    output logic        ledRed
);

    logic clk12mhz;

    IceboardTest_Blinky icestickSDRAMTest(
        .clk12mhz(clk12mhz),
        .ledRed(ledRed)
    );

    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, IceboardTest_BlinkySim);

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

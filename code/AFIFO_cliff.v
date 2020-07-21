`default_nettype	none
//
//
module afifo(i_wclk, i_wr, i_wdata, o_wfull,
		i_rclk, i_rd, o_rdata, o_rempty_);
	parameter	DSIZE = 2,
			ASIZE = 4;
	localparam	DW = DSIZE,
			AW = ASIZE;
	input	wire			i_wclk, i_wr;
	input	wire	[DW-1:0]	i_wdata;
	output	reg			o_wfull;
	input	wire			i_rclk, i_rd;
	output	wire	[DW-1:0]	o_rdata;
	output	reg			o_rempty_;

	wire	[AW-1:0]	waddr, raddr;
	wire			wfull_next, rempty__next;
	reg	[AW:0]		wgray, wbin, wq2_rgray, wq1_rgray,
				rgray, rbin, rq2_wgray, rq1_wgray;
	//
	wire	[AW:0]		wgraynext, wbinnext;
	wire	[AW:0]		rgraynext, rbinnext;

	reg	[DW-1:0]	mem	[0:((1<<AW)-1)];

	/////////////////////////////////////////////
	//
	//
	// Write logic
	//
	//
	/////////////////////////////////////////////

	//
	// Cross clock domains
	//
	// Cross the read Gray pointer into the write clock domain
    // initial    { wq2_rgray,  wq1_rgray } = 0;
	always @(posedge i_wclk)
		{ wq2_rgray, wq1_rgray } <= { wq1_rgray, rgray };



	// Calculate the next write address, and the next graycode pointer.
	assign	wbinnext  = wbin + { {(AW){1'b0}}, ((i_wr) && (!o_wfull)) };
	assign	wgraynext = (wbinnext >> 1) ^ wbinnext;

	assign	waddr = wbin[AW-1:0];

	// Register these two values--the address and its Gray code
	// representation
    // initial    { wbin, wgray } = 0;
	always @(posedge i_wclk)
		{ wbin, wgray } <= { wbinnext, wgraynext };

	assign	wfull_next = (wgraynext == { ~wq2_rgray[AW:AW-1],
				wq2_rgray[AW-2:0] });

	//
	// Calculate whether or not the register will be full on the next
	// clock.
    // initial    o_wfull = 0;
	always @(posedge i_wclk)
		o_wfull <= wfull_next;

	//
	// Write to the FIFO on a clock
	always @(posedge i_wclk)
	if ((i_wr)&&(!o_wfull))
		mem[waddr] <= i_wdata;

	////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////
	//
	//
	// Read logic
	//
	//
	////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////
	//
	//

	//
	// Cross clock domains
	//
	// Cross the write Gray pointer into the read clock domain
    // initial    { rq2_wgray,  rq1_wgray } = 0;
	always @(posedge i_rclk)
		{ rq2_wgray, rq1_wgray } <= { rq1_wgray, wgray };


	// Calculate the next read address,
	assign	rbinnext  = rbin + { {(AW){1'b0}}, ((i_rd)&&(o_rempty_)) };
	// and the next Gray code version associated with it
	assign	rgraynext = (rbinnext >> 1) ^ rbinnext;

	// Register these two values, the read address and the Gray code version
	// of it, on the next read clock
	//
    // initial    { rbin, rgray } = 0;
	always @(posedge i_rclk)
		{ rbin, rgray } <= { rbinnext, rgraynext };

	// Memory read address Gray code and pointer calculation
	assign	raddr = rbin[AW-1:0];

	// Determine if we'll be empty on the next clock
	assign	rempty__next = (rgraynext != rq2_wgray);

    // initial o_rempty_ = 0;
	always @(posedge i_rclk)
		o_rempty_ <= rempty__next;

	//
	// Read from the memory--a clockless read here, clocked by the next
	// read FLOP in the next processing stage (somewhere else)
	//
	assign	o_rdata = mem[raddr];
endmodule
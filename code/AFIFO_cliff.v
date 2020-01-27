`default_nettype	none
//
//
module afifo(i_wclk, i_wrst_n, i_wr, i_wdata, o_wfull,
		i_rclk, i_rrst_n, i_rd, o_rdata, o_rempty);
	parameter	DSIZE = 2,
			ASIZE = 4;
	localparam	DW = DSIZE,
			AW = ASIZE;
	input	wire			i_wclk, i_wrst_n, i_wr;
	input	wire	[DW-1:0]	i_wdata;
	output	reg			o_wfull;
	input	wire			i_rclk, i_rrst_n, i_rd;
	output	wire	[DW-1:0]	o_rdata;
	output	reg			o_rempty;

	wire	[AW-1:0]	waddr, raddr;
	wire			wfull_next, rempty_next;
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
	initial	{ wq2_rgray,  wq1_rgray } = 0;
	always @(posedge i_wclk or negedge i_wrst_n)
	if (!i_wrst_n)
		{ wq2_rgray, wq1_rgray } <= 0;
	else
		{ wq2_rgray, wq1_rgray } <= { wq1_rgray, rgray };



	// Calculate the next write address, and the next graycode pointer.
	assign	wbinnext  = wbin + { {(AW){1'b0}}, ((i_wr) && (!o_wfull)) };
	assign	wgraynext = (wbinnext >> 1) ^ wbinnext;

	assign	waddr = wbin[AW-1:0];

	// Register these two values--the address and its Gray code
	// representation
	initial	{ wbin, wgray } = 0;
	always @(posedge i_wclk or negedge i_wrst_n)
	if (!i_wrst_n)
		{ wbin, wgray } <= 0;
	else
		{ wbin, wgray } <= { wbinnext, wgraynext };

	assign	wfull_next = (wgraynext == { ~wq2_rgray[AW:AW-1],
				wq2_rgray[AW-2:0] });

	//
	// Calculate whether or not the register will be full on the next
	// clock.
	initial	o_wfull = 0;
	always @(posedge i_wclk or negedge i_wrst_n)
	if (!i_wrst_n)
		o_wfull <= 1'b0;
	else
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
	initial	{ rq2_wgray,  rq1_wgray } = 0;
	always @(posedge i_rclk or negedge i_rrst_n)
	if (!i_rrst_n)
		{ rq2_wgray, rq1_wgray } <= 0;
	else
		{ rq2_wgray, rq1_wgray } <= { rq1_wgray, wgray };


	// Calculate the next read address,
	assign	rbinnext  = rbin + { {(AW){1'b0}}, ((i_rd)&&(!o_rempty)) };
	// and the next Gray code version associated with it
	assign	rgraynext = (rbinnext >> 1) ^ rbinnext;

	// Register these two values, the read address and the Gray code version
	// of it, on the next read clock
	//
	initial	{ rbin, rgray } = 0;
	always @(posedge i_rclk or negedge i_rrst_n)
	if (!i_rrst_n)
		{ rbin, rgray } <= 0;
	else
		{ rbin, rgray } <= { rbinnext, rgraynext };

	// Memory read address Gray code and pointer calculation
	assign	raddr = rbin[AW-1:0];

	// Determine if we'll be empty on the next clock
	assign	rempty_next = (rgraynext == rq2_wgray);

	initial o_rempty = 1;
	always @(posedge i_rclk or negedge i_rrst_n)
	if (!i_rrst_n)
		o_rempty <= 1'b1;
	else
		o_rempty <= rempty_next;

	//
	// Read from the memory--a clockless read here, clocked by the next
	// read FLOP in the next processing stage (somewhere else)
	//
	assign	o_rdata = mem[raddr];
endmodule
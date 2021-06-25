////////////////////////////////////////////////////////////////////////
//[Disclaimer]    
//This software code and all associated documentation, comments
//or other information (collectively "Software") is provided 
//"AS IS" without warranty of any kind. MICRON TECHNOLOGY, INC. 
//("MTI") EXPRESSLY DISCLAIMS ALL WARRANTIES EXPRESS OR IMPLIED,
//INCLUDING BUT NOT LIMITED TO, NONINFRINGEMENT OF THIRD PARTY
//RIGHTS, AND ANY IMPLIED WARRANTIES OF MERCHANTABILITY OR FITNESS
//FOR ANY PARTICULAR PURPOSE. MTI DOES NOT WARRANT THAT THE
//SOFTWARE WILL MEET YOUR REQUIREMENTS, OR THAT THE OPERATION OF
//THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE. FURTHERMORE,
//MTI DOES NOT MAKE ANY REPRESENTATIONS REGARDING THE USE OR THE
//RESULTS OF THE USE OF THE SOFTWARE IN TERMS OF ITS CORRECTNESS,
//ACCURACY, RELIABILITY, OR OTHERWISE. THE ENTIRE RISK ARISING OUT
//OF USE OR PERFORMANCE OF THE SOFTWARE REMAINS WITH YOU. IN NO
//EVENT SHALL MTI, ITS AFFILIATED COMPANIES OR THEIR SUPPLIERS BE
//LIABLE FOR ANY DIRECT, INDIRECT, CONSEQUENTIAL, INCIDENTAL, OR
//SPECIAL DAMAGES (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS
//OF PROFITS, BUSINESS INTERRUPTION, OR LOSS OF INFORMATION)
//ARISING OUT OF YOUR USE OF OR INABILITY TO USE THE SOFTWARE,
//EVEN IF MTI HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
//Because some jurisdictions prohibit the exclusion or limitation
//of liability for consequential or incidental damages, the above
//limitation may not apply to you.
//
//Copyright 2008 Micron Technology, Inc. All rights reserved.
////////////////////////////////////////////////////////////////////////

// Testbench for Micron SDR SDRAM Verilog models

`timescale 1ps / 1ps

module tb;

`include "mobile_sdr_parameters.vh"

reg                          CLK         ;                  // Clock                                
reg                          CKE         ;                  // Synchronous Clock Enable             
reg       [ADDR_BITS - 1: 0] ADDR        ;                  // SDRAM Address                        
reg       [BA_BITS - 1 : 0]  BA          ;                  // Bank Address                         
reg                          CS_N        ;                  // CS#                                  
reg                          RAS_N       ;                  // RAS#                                 
reg                          CAS_N       ;                  // CAS#                                 
reg                          WE_N        ;                  // WE#                                  
reg       [DQ_BITS - 1 : 0]  Dq          ;
reg       [DM_BITS - 1 : 0]  Dm          ;
reg       [DM_BITS - 1 : 0]  DM          ;                  // I/O Mask

reg                [12 : 0] mode_reg    ;                   //Mode Register
reg                [12 : 0] ext_mode_reg;                   //Extended Mode Register

wire                [7 : 0] bl_rd    = (1<<mode_reg[2:0]);  //Read Burst Length
wire                [7 : 0] bl       = bl_rd             ;  //Burst Length
wire                [7 : 0] bl_wr    = (mode_reg[9]) ? 1 : (1<<mode_reg[2:0]);  //Write Burst Length
wire                [2 : 0] CL       = (mode_reg[6:4])   ;  //CAS Latency
wire                [3 : 0] WL       = 0                 ;  //Write Latency

integer                     bc_dm                        ;
integer                     bc_dq                        ;
reg                         Dq_en                        ;
reg                         Dm_en                        ;
integer                     bc_dm_sel                    ;

wire    [DQ_BITS   - 1 : 0] DQ       = (Dq_en)? Dq : 'bz ;
always @* begin
    DM       = (Dm_en)? Dm : 'b0 ;
end

// Read Verify Signals
reg                     valid_burst_n ;
reg [ DQ_BITS-1    : 0] expected_data ;
reg [ 16*DQ_BITS-1 : 0] comp_dm_bits  ;
reg [ 16*DQ_BITS-1 : 0] comp_dq       ;
reg                     verify_data   ;
//integer                 cas_count     ;
integer                 bl_count      ;

// new compare begin
reg [ DQ_BITS-1:0] DQ_COMPARE_FIFO [16+3:0] ;
reg [ DQ_BITS-1:0] DM_COMPARE_FIFO [16+3:0] ;

reg CLK_DEL ;

always @ (CLK)
    CLK_DEL <= # 2800 CLK ;


always @ (posedge CLK_DEL)
begin : FIFO
    integer i ;
    for (i = 0; i < 16+3; i = i + 1)
    begin
        DQ_COMPARE_FIFO[i] = DQ_COMPARE_FIFO[i+1] ;
        DM_COMPARE_FIFO[i] = DM_COMPARE_FIFO[i+1] ;
    end
    
    #1

    if (verify_data)
    begin
        if (DQ !== (DQ_COMPARE_FIFO[0] & ~DM_COMPARE_FIFO[0]))
        begin
            $display ("Error - Data Miscompare Expect: 0x%h, Actual: 0x%h at time %t", DQ_COMPARE_FIFO[0], DQ, $time);
        end
    end
end
// new compare end

reg Test_done;

parameter            hi_z = 32'hzzzzzzzz;                   // Hi-Z


mobile_sdr mobile_sdr (
    .clk    ( CLK_DEL   ), 
    .cke    ( CKE   ), 
    .addr   ( ADDR  ), 
    .ba     ( BA    ), 
    .cs_n   ( CS_N  ), 
    .ras_n  ( RAS_N ), 
    .cas_n  ( CAS_N ), 
    .we_n   ( WE_N  ), 
    .dq     ( DQ    ), 
    .dqm    ( DM    )
);

initial begin
    $timeformat (-9, 3, " ns", 1);
    CLK = 1'b0;
    CKE = 1'b1;
    CS_N = 1'b1;
    Dq  = hi_z;
    bc_dq = 16 ;
    bc_dm = 19 ;
    Dq_en = 1'b0;
    Dm_en = 1'b0;
end

// timing definition in tck units
real    tck   ;
integer trc   ;
integer trrd  ;
integer trcd  ;
integer tras  ;
integer twr   ;
integer trp   ;
integer tmrd  ;
integer trfc  ;

initial begin
`ifdef period
        tck = `period ; 
`else
        tck =  tCK;
`endif
        //tccd   = TCCD;
        trc    = ceil(tRC/tck);
//        trrd   = ceil(tRRD/tck);
        trcd   = ceil(tRCD/tck);
        tras   = ceil(tRAS/tck);
        twr    = ceil(tWRm/tck);
        trp    = ceil(tRP/tck);
        tmrd   = tMRD;
        trfc   = ceil(tRFC/tck);
end

function integer ceil;
    input number;
    real number;
    if (number > $rtoi(number))
        ceil = $rtoi(number) + 1;
    else
        ceil = number;
endfunction

reg clk_en;
initial clk_en = 1'b1;

//always #4.8 CLK = ~CLK;
always begin
    # (tck/2);
    CLK   = ~CLK & clk_en;
end

task activate;
    input   [BA_BITS - 1 : 0] bank;
    input  [ROW_BITS - 1 : 0] row;
    begin
        CKE     = 1'b1;
        CS_N    = 1'b0;
        RAS_N   = 1'b0;
        CAS_N   = 1'b1;
        WE_N    = 1'b1;
        BA      = bank;
        ADDR    = row;//addr;
        # tck;
    end
endtask

task refresh;
    begin
        CKE   = 1;
        CS_N  = 0;
        RAS_N = 0;
        CAS_N = 0;
        WE_N  = 1;
        Dm    = 0;
        BA    = 0;
        ADDR  = 0;
        Dq    = hi_z;
        # tck;
    end
endtask

task burst_term;
    begin
        CKE   = 1;
        CS_N  = 0;
        RAS_N = 1;
        CAS_N = 1;
        WE_N  = 0;
        Dm    = 0;
        BA    = 0;
        ADDR  = 0;
        Dq    = hi_z;
		# tck;
    end
endtask


task load_mode;
    input [01 : 00] ba;
    input [12 : 00] addr;
    begin
        case (ba)
            2'b00:  begin
                      mode_reg = addr; 
                    end
            2'b10:  begin
                       ext_mode_reg = addr; 
                    end
        endcase
        CKE     = 1;
        CS_N    = 0;
        RAS_N   = 0;
        CAS_N   = 0;
        WE_N    = 0;
        Dm      = 0;
        BA      = ba;
        ADDR    = addr;
        Dq      = hi_z;
        # tck;
    end
endtask



task nop;
    input  count;
    integer count;
    begin
        if (count<0) begin
            count = 0;
        end
        if (count>0) begin
            CKE     =  1'b1;
            CS_N    =  1'b0;
            RAS_N   =  1'b1;
            CAS_N   =  1'b1;
            WE_N    =  1'b1;
            Dm      =  0;
            # (count*tck);
        end
    end
endtask

task power_up;
    input delay; // in nanoseconds - this is here ONLY so we can test an invalid delay.  Normally the delay will be 200000.
	integer delay;
    begin
        CKE     =  1'b1;
        # (10*tck);
//            $display ("%m at time %t TB:  A 200 us delay is required before CKE can be brought high.", $time);
        @ (negedge CLK) CKE     =  1'b1;
        nop (delay/tck+1);
    end
endtask

task precharge;
    input   [BA_BITS - 1 : 0] bank;
    input                     ap; //precharge all
    begin
        CKE     = 1'b1;
        CS_N    = 1'b0;
        RAS_N   = 1'b0;
        CAS_N   = 1'b1;
        WE_N    = 1'b0;
        BA      = bank;
        ADDR    = (ap<<10);//addr;
        # tck;
    end
endtask

reg [16*DM_BITS   - 1 : 0] dm_task_data ;

// read without data verification - copied from Mpls tb by baaaab 05/18/06
task read;
    input    [BA_BITS - 1 : 0] bank;
    input   [COL_BITS - 1 : 0] col;
    input                      ap; //Auto Precharge
    input [16*DM_BITS   - 1 : 0] dm;
    reg    [ADDR_BITS - 1 : 0] atemp [1:0];
    integer i;
    begin
        CKE     = 1'b1;
        CS_N    = 1'b0;
        RAS_N   = 1'b1;
        CAS_N   = 1'b0;
        WE_N    = 1'b1;
        Dm      = 0;
        BA      = bank;
        atemp[0] = col & 10'h3ff;   //addr[ 9: 0] = COL[ 9: 0]
        atemp[1] = (col>>10)<<11;   //addr[ N:11] = COL[ N:10]
        ADDR = atemp[0] | atemp[1] | (ap<<10);
        dm_task_data <= #(CL*tck-0.5*tck) dm;
        Dm_en <= #(CL*tck-0.5*tck) 1'b1;
        bc_dm = 0;
        # tck;
    end
endtask
wire [31:0] tAC = (CL == 3) ? tAC3 :
                  (CL == 2) ? tAC2 :
                              0    ;
task read_verify;
    input                      we;
    input    [BA_BITS - 1 : 0] bank;
    input   [COL_BITS - 1 : 0] col;
    input                      ap; //Auto Precharge
    input [16*DM_BITS - 1 : 0] dm_out;
    input [16*DM_BITS - 1 : 0] dm;
    input [16*DQ_BITS - 1 : 0] dq;
    reg    [ADDR_BITS - 1 : 0] atemp [1:0];
    integer i,j;
    reg larger ;
    begin
        CKE     = 1'b1;
        CS_N    = 1'b0;
        RAS_N   = 1'b1;
        CAS_N   = 1'b0;
        WE_N    = 1'b1;
        Dm      = dm;
        BA      = bank;
        atemp[0] = col & 10'h3ff;   //addr[ 9: 0] = COL[ 9: 0]
        atemp[1] = (col>>10)<<11;   //addr[ N:11] = COL[ N:10]
        ADDR = atemp[0] | atemp[1] | (ap<<10);
        dm_task_data <= #(CL*tck-0.5*tck) dm_out;
        Dm_en <= #(CL*tck-0.5*tck) 1'b1;
        bc_dm = 0;
        for (i=0; i<(DQ_BITS*16); i=i+1) begin
            comp_dm_bits[i] <= dm[i/8];
        end
        comp_dq <= #(CL*tck-0.5*tck) dq;
//        verify_data <= #(CL*tck+0.34*tck) 1'b1;
        verify_data <= #((0.5+CL-1)*tck+tAC) 1'b1;
        bl_count <= #(CL*tck-0.16*tck) 0;
//        cas_count <= 0;
        larger = (tAC >= tck) ;
        for (i=0; i<bl_rd; i=i+1) 
        begin
            DQ_COMPARE_FIFO[1+larger+i+CL] = dq>>(i*DQ_BITS);
            for (j=0;j<DQ_BITS;j=j+1)
//                DM_COMPARE_FIFO[1+larger+i+CL][j] = dm[i/8]>>(i*DM_BITS);
                DM_COMPARE_FIFO[1+larger+i+CL][j] = dm>>(i*DM_BITS+(i/8));

        end
        # tck;
    end
endtask

//    //write task supports burst lengths <= 16

reg [16*DQ_BITS   - 1 : 0] dq_task_data ;

task write;
    input                        we ;
    input      [BA_BITS - 1 : 0] bank;
    input     [COL_BITS - 1 : 0] col;
    input                        ap; //Auto Precharge
    input [16*DM_BITS   - 1 : 0] dm;
    input [16*DQ_BITS   - 1 : 0] dq;
    reg      [ADDR_BITS - 1 : 0] atemp [1:0];
    integer i;
    begin
        CKE     = 1'b1;
        CS_N    = 1'b0;
        RAS_N   = 1'b1;
        CAS_N   = 1'b0;
        WE_N    = 1'b0;
        BA      =   bank;
        atemp[0] = col & 10'h3ff;   //addr[ 9: 0] = COL[ 9: 0]
        atemp[1] = (col>>10)<<11;   //addr[ N:11] = COL[ N:10]
        ADDR = atemp[0] | atemp[1] | (ap<<10);
        Dq_en = 1'b1 ;
        Dm_en = 1'b1 ;
        bc_dq = 0;
        bc_dm = CL;
        dm_task_data = dm;
        dq_task_data = dq;
        bl_count = 16+CL+1;
        verify_data = 0 ;
        #tck;  
    end
endtask
task test_done;
    Test_done = 1'b1 ;
endtask

always @(negedge CLK) begin
    if (bc_dq<16) begin
        bc_dq=bc_dq+1;
    end
    if (bc_dq<=bl_wr) begin
        case (bc_dq)
            16: Dq  <= dq_task_data[16*DQ_BITS-1 : 15*DQ_BITS];
            15: Dq  <= dq_task_data[15*DQ_BITS-1 : 14*DQ_BITS];
            14: Dq  <= dq_task_data[14*DQ_BITS-1 : 13*DQ_BITS];
            13: Dq  <= dq_task_data[13*DQ_BITS-1 : 12*DQ_BITS];
            12: Dq  <= dq_task_data[12*DQ_BITS-1 : 11*DQ_BITS];
            11: Dq  <= dq_task_data[11*DQ_BITS-1 : 10*DQ_BITS];
            10: Dq  <= dq_task_data[10*DQ_BITS-1 :  9*DQ_BITS];
             9: Dq  <= dq_task_data[ 9*DQ_BITS-1 :  8*DQ_BITS];
             8: Dq  <= dq_task_data[ 8*DQ_BITS-1 :  7*DQ_BITS];
             7: Dq  <= dq_task_data[ 7*DQ_BITS-1 :  6*DQ_BITS];
             6: Dq  <= dq_task_data[ 6*DQ_BITS-1 :  5*DQ_BITS];
             5: Dq  <= dq_task_data[ 5*DQ_BITS-1 :  4*DQ_BITS];
             4: Dq  <= dq_task_data[ 4*DQ_BITS-1 :  3*DQ_BITS];
             3: Dq  <= dq_task_data[ 3*DQ_BITS-1 :  2*DQ_BITS];
             2: Dq  <= dq_task_data[ 2*DQ_BITS-1 :  1*DQ_BITS];
             1: Dq  <= dq_task_data[ 1*DQ_BITS-1 :  0*DQ_BITS];
        endcase
    end else if (bc_dq == (bl_wr+1)) begin
        Dq_en = 1'b0 ;
    end
end

always @(negedge CLK) begin
    if (bc_dm<(16+CL)) begin
        bc_dm=bc_dm+1;
    end
    if (bc_dm<=(bl_wr+CL)) begin
        bc_dm_sel <= bc_dm-CL+1 ;
        case (bc_dm_sel)
            16: Dm  <= dm_task_data[16*DM_BITS-1 : 15*DM_BITS];
            15: Dm  <= dm_task_data[15*DM_BITS-1 : 14*DM_BITS];
            14: Dm  <= dm_task_data[14*DM_BITS-1 : 13*DM_BITS];
            13: Dm  <= dm_task_data[13*DM_BITS-1 : 12*DM_BITS];
            12: Dm  <= dm_task_data[12*DM_BITS-1 : 11*DM_BITS];
            11: Dm  <= dm_task_data[11*DM_BITS-1 : 10*DM_BITS];
            10: Dm  <= dm_task_data[10*DM_BITS-1 :  9*DM_BITS];
             9: Dm  <= dm_task_data[ 9*DM_BITS-1 :  8*DM_BITS];
             8: Dm  <= dm_task_data[ 8*DM_BITS-1 :  7*DM_BITS];
             7: Dm  <= dm_task_data[ 7*DM_BITS-1 :  6*DM_BITS];
             6: Dm  <= dm_task_data[ 6*DM_BITS-1 :  5*DM_BITS];
             5: Dm  <= dm_task_data[ 5*DM_BITS-1 :  4*DM_BITS];
             4: Dm  <= dm_task_data[ 4*DM_BITS-1 :  3*DM_BITS];
             3: Dm  <= dm_task_data[ 3*DM_BITS-1 :  2*DM_BITS];
             2: Dm  <= dm_task_data[ 2*DM_BITS-1 :  1*DM_BITS];
             1: Dm  <= dm_task_data[ 1*DM_BITS-1 :  0*DM_BITS];
        endcase
    end else if (bc_dm == (bl_wr+CL+1)) begin
        Dm_en = 1'b0 ;
    end
end

//Data Verification Logic 
always @(posedge CLK) begin
//    if (cas_count==CL) begin
//        bl_count=0;
//        cas_count = cas_count+1;
//    end else if (cas_count<8) begin
//        cas_count = cas_count+1;
//    end
    if (bl_count<(16+CL+1)) begin
        bl_count=bl_count+1;
    end
    if (bl_count<=bl_rd) begin
        case (bl_count)
            16: valid_burst_n = |( ( (comp_dq[ 16*DQ_BITS-1 : 15*DQ_BITS] & ~comp_dm_bits[ 16*DQ_BITS-1 : 15*DQ_BITS])^(DQ & ~comp_dm_bits[ 16*DQ_BITS-1 : 15*DQ_BITS]) ) & {DQ_BITS{verify_data}});
            15: valid_burst_n = |( ( (comp_dq[ 15*DQ_BITS-1 : 14*DQ_BITS] & ~comp_dm_bits[ 15*DQ_BITS-1 : 14*DQ_BITS])^(DQ & ~comp_dm_bits[ 15*DQ_BITS-1 : 14*DQ_BITS]) ) & {DQ_BITS{verify_data}});
            14: valid_burst_n = |( ( (comp_dq[ 14*DQ_BITS-1 : 13*DQ_BITS] & ~comp_dm_bits[ 14*DQ_BITS-1 : 13*DQ_BITS])^(DQ & ~comp_dm_bits[ 14*DQ_BITS-1 : 13*DQ_BITS]) ) & {DQ_BITS{verify_data}});
            13: valid_burst_n = |( ( (comp_dq[ 13*DQ_BITS-1 : 12*DQ_BITS] & ~comp_dm_bits[ 13*DQ_BITS-1 : 12*DQ_BITS])^(DQ & ~comp_dm_bits[ 13*DQ_BITS-1 : 12*DQ_BITS]) ) & {DQ_BITS{verify_data}});
            12: valid_burst_n = |( ( (comp_dq[ 12*DQ_BITS-1 : 11*DQ_BITS] & ~comp_dm_bits[ 12*DQ_BITS-1 : 11*DQ_BITS])^(DQ & ~comp_dm_bits[ 12*DQ_BITS-1 : 11*DQ_BITS]) ) & {DQ_BITS{verify_data}});
            11: valid_burst_n = |( ( (comp_dq[ 11*DQ_BITS-1 : 10*DQ_BITS] & ~comp_dm_bits[ 11*DQ_BITS-1 : 10*DQ_BITS])^(DQ & ~comp_dm_bits[ 11*DQ_BITS-1 : 10*DQ_BITS]) ) & {DQ_BITS{verify_data}});
            10: valid_burst_n = |( ( (comp_dq[ 10*DQ_BITS-1 :  9*DQ_BITS] & ~comp_dm_bits[ 10*DQ_BITS-1 :  9*DQ_BITS])^(DQ & ~comp_dm_bits[ 10*DQ_BITS-1 :  9*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             9: valid_burst_n = |( ( (comp_dq[  9*DQ_BITS-1 :  8*DQ_BITS] & ~comp_dm_bits[  9*DQ_BITS-1 :  8*DQ_BITS])^(DQ & ~comp_dm_bits[  9*DQ_BITS-1 :  8*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             8: valid_burst_n = |( ( (comp_dq[  8*DQ_BITS-1 :  7*DQ_BITS] & ~comp_dm_bits[  8*DQ_BITS-1 :  7*DQ_BITS])^(DQ & ~comp_dm_bits[  8*DQ_BITS-1 :  7*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             7: valid_burst_n = |( ( (comp_dq[  7*DQ_BITS-1 :  6*DQ_BITS] & ~comp_dm_bits[  7*DQ_BITS-1 :  6*DQ_BITS])^(DQ & ~comp_dm_bits[  7*DQ_BITS-1 :  6*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             6: valid_burst_n = |( ( (comp_dq[  6*DQ_BITS-1 :  5*DQ_BITS] & ~comp_dm_bits[  6*DQ_BITS-1 :  5*DQ_BITS])^(DQ & ~comp_dm_bits[  6*DQ_BITS-1 :  5*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             5: valid_burst_n = |( ( (comp_dq[  5*DQ_BITS-1 :  4*DQ_BITS] & ~comp_dm_bits[  5*DQ_BITS-1 :  4*DQ_BITS])^(DQ & ~comp_dm_bits[  5*DQ_BITS-1 :  4*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             4: valid_burst_n = |( ( (comp_dq[  4*DQ_BITS-1 :  3*DQ_BITS] & ~comp_dm_bits[  4*DQ_BITS-1 :  3*DQ_BITS])^(DQ & ~comp_dm_bits[  4*DQ_BITS-1 :  3*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             3: valid_burst_n = |( ( (comp_dq[  3*DQ_BITS-1 :  2*DQ_BITS] & ~comp_dm_bits[  3*DQ_BITS-1 :  2*DQ_BITS])^(DQ & ~comp_dm_bits[  3*DQ_BITS-1 :  2*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             2: valid_burst_n = |( ( (comp_dq[  2*DQ_BITS-1 :  1*DQ_BITS] & ~comp_dm_bits[  2*DQ_BITS-1 :  1*DQ_BITS])^(DQ & ~comp_dm_bits[  2*DQ_BITS-1 :  1*DQ_BITS]) ) & {DQ_BITS{verify_data}});
             1: valid_burst_n = |( ( (comp_dq[  1*DQ_BITS-1 :  0*DQ_BITS] & ~comp_dm_bits[  1*DQ_BITS-1 :  0*DQ_BITS])^(DQ & ~comp_dm_bits[  1*DQ_BITS-1 :  0*DQ_BITS]) ) & {DQ_BITS{verify_data}});
            default: 
            begin
            valid_burst_n <= 1'b0;
            $display("Down here!!");
            end
        endcase
        case (bl_count)
            16: expected_data = (comp_dq[ 16*DQ_BITS-1 : 15*DQ_BITS]) | ((comp_dm_bits[ 16*DQ_BITS-1 : 15*DQ_BITS]) & ({DQ_BITS{1'bx}}));
            15: expected_data = (comp_dq[ 15*DQ_BITS-1 : 14*DQ_BITS]) | ((comp_dm_bits[ 15*DQ_BITS-1 : 14*DQ_BITS]) & ({DQ_BITS{1'bx}}));
            14: expected_data = (comp_dq[ 14*DQ_BITS-1 : 13*DQ_BITS]) | ((comp_dm_bits[ 14*DQ_BITS-1 : 13*DQ_BITS]) & ({DQ_BITS{1'bx}}));
            13: expected_data = (comp_dq[ 13*DQ_BITS-1 : 12*DQ_BITS]) | ((comp_dm_bits[ 13*DQ_BITS-1 : 12*DQ_BITS]) & ({DQ_BITS{1'bx}}));
            12: expected_data = (comp_dq[ 12*DQ_BITS-1 : 11*DQ_BITS]) | ((comp_dm_bits[ 12*DQ_BITS-1 : 11*DQ_BITS]) & ({DQ_BITS{1'bx}}));
            11: expected_data = (comp_dq[ 11*DQ_BITS-1 : 10*DQ_BITS]) | ((comp_dm_bits[ 11*DQ_BITS-1 : 10*DQ_BITS]) & ({DQ_BITS{1'bx}}));
            10: expected_data = (comp_dq[ 10*DQ_BITS-1 :  9*DQ_BITS]) | ((comp_dm_bits[ 10*DQ_BITS-1 :  9*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             9: expected_data = (comp_dq[  9*DQ_BITS-1 :  8*DQ_BITS]) | ((comp_dm_bits[  9*DQ_BITS-1 :  8*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             8: expected_data = (comp_dq[  8*DQ_BITS-1 :  7*DQ_BITS]) | ((comp_dm_bits[  8*DQ_BITS-1 :  7*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             7: expected_data = (comp_dq[  7*DQ_BITS-1 :  6*DQ_BITS]) | ((comp_dm_bits[  7*DQ_BITS-1 :  6*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             6: expected_data = (comp_dq[  6*DQ_BITS-1 :  5*DQ_BITS]) | ((comp_dm_bits[  6*DQ_BITS-1 :  5*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             5: expected_data = (comp_dq[  5*DQ_BITS-1 :  4*DQ_BITS]) | ((comp_dm_bits[  5*DQ_BITS-1 :  4*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             4: expected_data = (comp_dq[  4*DQ_BITS-1 :  3*DQ_BITS]) | ((comp_dm_bits[  4*DQ_BITS-1 :  3*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             3: expected_data = (comp_dq[  3*DQ_BITS-1 :  2*DQ_BITS]) | ((comp_dm_bits[  3*DQ_BITS-1 :  2*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             2: expected_data = (comp_dq[  2*DQ_BITS-1 :  1*DQ_BITS]) | ((comp_dm_bits[  2*DQ_BITS-1 :  1*DQ_BITS]) & ({DQ_BITS{1'bx}}));
             1: expected_data = (comp_dq[  1*DQ_BITS-1 :  0*DQ_BITS]) | ((comp_dm_bits[  1*DQ_BITS-1 :  0*DQ_BITS]) & ({DQ_BITS{1'bx}}));
            default: expected_data <= 'b0;
        endcase
        if (valid_burst_n == 1'b1) begin
//            $display ("%m at time %t ERROR: Expected Data = %h, Read Data = %h, Burst = %d", $time, expected_data, DQ, bl_count);
        end
    end
    if (bl_count == bl_rd+1) begin
        verify_data <= 1'b0 ;
    end
end

always @(negedge CLK) begin
    if (verify_data == 1'b1) begin
        if (valid_burst_n == 1'b1) begin
//            $display ("%m at time %t ERROR: Expected Data = %h, Read Data = %h, Burst = %d", $time, expected_data, DQ, bl_count);
        end
    end
end

always @ (*)
begin
    if ((part_size == 64) | ((part_size == 128) & (tCK >= 7500)) ) // 64 Mb and Y25M  have tRRD spec'ed in ps, not CK
        trrd   = ceil(tRRD/tck);
    else
        trrd   = tRRD;
end

initial Test_done = 0;

// End-of-test triggered in 'subtest.vh'
always @(Test_done) begin : all_done
    if (Test_done == 1) begin
  #5000
  $display ("Simulation is Complete");
        $stop(0);
        $finish;
    end
end

    // Test included from external file
`include "subtest.vh"

endmodule



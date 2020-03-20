/****************************************************************************************
*
*   Disclaimer   This software code and all associated documentation, comments or other 
*  of Warranty:  information (collectively "Software") is provided "AS IS" without 
*                warranty of any kind. MICRON TECHNOLOGY, INC. ("MTI") EXPRESSLY 
*                DISCLAIMS ALL WARRANTIES EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
*                TO, NONINFRINGEMENT OF THIRD PARTY RIGHTS, AND ANY IMPLIED WARRANTIES 
*                OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE. MTI DOES NOT 
*                WARRANT THAT THE SOFTWARE WILL MEET YOUR REQUIREMENTS, OR THAT THE 
*                OPERATION OF THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE. 
*                FURTHERMORE, MTI DOES NOT MAKE ANY REPRESENTATIONS REGARDING THE USE OR 
*                THE RESULTS OF THE USE OF THE SOFTWARE IN TERMS OF ITS CORRECTNESS, 
*                ACCURACY, RELIABILITY, OR OTHERWISE. THE ENTIRE RISK ARISING OUT OF USE 
*                OR PERFORMANCE OF THE SOFTWARE REMAINS WITH YOU. IN NO EVENT SHALL MTI, 
*                ITS AFFILIATED COMPANIES OR THEIR SUPPLIERS BE LIABLE FOR ANY DIRECT, 
*                INDIRECT, CONSEQUENTIAL, INCIDENTAL, OR SPECIAL DAMAGES (INCLUDING, 
*                WITHOUT LIMITATION, DAMAGES FOR LOSS OF PROFITS, BUSINESS INTERRUPTION, 
*                OR LOSS OF INFORMATION) ARISING OUT OF YOUR USE OF OR INABILITY TO USE 
*                THE SOFTWARE, EVEN IF MTI HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH 
*                DAMAGES. Because some jurisdictions prohibit the exclusion or 
*                limitation of liability for consequential or incidental damages, the 
*                above limitation may not apply to you.
*
*                Copyright 2008 Micron Technology, Inc. All rights reserved.
*
****************************************************************************************/

    // x-x-xx ???  Timing parameters based on Speed Grade and part type (Y47M) 03/07
    // 2-5-08 clk  Updated parameters based off of 10/07 datasheet
    // 5-5-08 clk  Crossed Y47M over to be the 512Mb, updated paramters to Rev B (4/08)

`define sg75
`define x16

                                          // SYMBOL UNITS DESCRIPTION
                                          // ------ ----- -----------
`ifdef sg6                                 //              Timing Parameters for -75 (CL = 3)
    parameter tCK              =     6000; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK3_min         =     6000; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK2_min         =     9600; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK1_min         =        0; // tCK    ps    Nominal Clock Cycle Time
    parameter tAC3             =     5000; // tAC3   ps    Access time from CLK (pos edge) CL = 3
    parameter tAC2             =     8000; // tAC2   ps    Access time from CLK (pos edge) CL = 2
    parameter tAC1             =        0; // tAC1   ps    Parameter definition for compilation - CL = 1 illegal for sg75
    parameter tHZ3             =     5000; // tHZ3   ps    Data Out High Z time - CL = 3
    parameter tHZ2             =     8000; // tHZ2   ps    Data Out High Z time - CL = 2
    parameter tHZ1             =        0; // tHZ1   ps    Parameter definition for compilation - CL = 1 illegal for sg75
    parameter tOH              =     2500; // tOH    ps    Data Out Hold time
    parameter tMRD             =        2; // tMRD   tCK   Load Mode Register command cycle time (2 * tCK)
    parameter tRAS             =    42000; // tRAS   ps    Active to Precharge command time
    parameter tRC              =    60000; // tRC    ps    Active to Active/Auto Refresh command time
    parameter tRFC             =    97500; // tRFC   ps    Refresh to Refresh Command interval time
    parameter tRCD             =    18000; // tRCD   ps    Active to Read/Write command time
    parameter tRP              =    18000; // tRP    ps    Precharge command period
    parameter tRRD             =        2; // tRRD   tCK   Active bank a to Active bank b command time
    parameter tWRa             =     7500; // tWR    ps    Write recovery time (auto-precharge mode - must add 1 CLK)
    parameter tWRm             =    15000; // tWR    ps    Write recovery time
    parameter tCH              =     2500; // tCH    ps    Clock high level width
    parameter tCL              =     2500; // tCL    ps    Clock low level width
    parameter tXSR             =   120000; // tXSR   ps    Clock low level width
`else `ifdef sg75                          //              Timing Parameters for -8 (CL = 3)
    parameter tCK              =     7500; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK3_min         =     7500; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK2_min         =     9600; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK1_min         =        0; // tCK    ps    Nominal Clock Cycle Time
    parameter tAC3             =     5400; // tAC3   ps    Access time from CLK (pos edge) CL = 3
    parameter tAC2             =     8000; // tAC2   ps    Access time from CLK (pos edge) CL = 2
    parameter tAC1             =        0; // tAC1   ps    Access time from CLK (pos edge) CL = 1
    parameter tHZ3             =     5400; // tHZ3   ps    Data Out High Z time - CL = 3
    parameter tHZ2             =     8000; // tHZ2   ps    Data Out High Z time - CL = 2
    parameter tHZ1             =        0; // tHZ1   ps    Data Out High Z time - CL = 1
    parameter tOH              =     2500; // tOH    ps    Data Out Hold time
    parameter tMRD             =        2; // tMRD   tCK   Load Mode Register command cycle time (2 * tCK)
    parameter tRAS             =    45000; // tRAS   ps    Active to Precharge command time
    parameter tRC              =    67500; // tRC    ps    Active to Active/Auto Refresh command time
    parameter tRFC             =    97500; // tRFC   ps    Refresh to Refresh Command interval time
    parameter tRCD             =    19200; // tRCD   ps    Active to Read/Write command time
    parameter tRP              =    19200; // tRP    ps    Precharge command period
    parameter tRRD             =        2; // tRRD   tCK   Active bank a to Active bank b command time (2 * tCK)
    parameter tWRa             =     7500; // tWR    ps    Write recovery time (auto-precharge mode - must add 1 CLK)
    parameter tWRm             =    15000; // tWR    ps    Write recovery time
    parameter tCH              =     2500; // tCH    ps    Clock high level width
    parameter tCL              =     2500; // tCL    ps    Clock low level width
    parameter tXSR             =   120000; // tXSR   ps    Clock low level width
`endif `endif 

    // Size Parameters based on Part Width

`ifdef x32
    parameter ADDR_BITS        =      13; // Set this parameter to control how many Address bits are used
    parameter ROW_BITS         =      13; // Set this parameter to control how many Row bits are used
    parameter DQ_BITS          =      32; // Set this parameter to control how many Data bits are used
    parameter DM_BITS          =       4; // Set this parameter to control how many DM bits are used
    parameter COL_BITS         =       9; // Set this parameter to control how many Column bits are used
    parameter BA_BITS          =       2; // Bank bits
`else `ifdef x16
    parameter ADDR_BITS        =      13; // Set this parameter to control how many Address bits are used
    parameter ROW_BITS         =      13; // Set this parameter to control how many Row bits are used
    parameter DQ_BITS          =      16; // Set this parameter to control how many Data bits are used
    parameter DM_BITS          =       2; // Set this parameter to control how many DM bits are used
    parameter COL_BITS         =      10; // Set this parameter to control how many Column bits are used
    parameter BA_BITS          =       2; // Bank bits
`endif `endif

    // Other Parameters

    parameter full_mem_bits    = BA_BITS+ADDR_BITS+COL_BITS; // Set this parameter to control how many unique addresses are used
    parameter part_mem_bits    = 10;                         // For fast sim load
    parameter part_size        = 512;                        // Set this parameter to indicate part size(512Mb, 256Mb, 128Mb)
    parameter CL_MAX           = 3;                          // Maximum Cas Latency Setting


#include <msp430g2553.h>

#define F_BYTE                     8
#define F_WORD                     16
#define F_ADDR                     20
#define F_LONG                     32

//! \brief Maximum number of tries for the determination of the core
//! identification info
#define MAX_ENTRY_TRY  4

//----------------------------------------------------------------------------
// Constants for the JTAG instruction register (IR) require LSB first.
// The MSB has been interchanged with LSB due to use of the same shifting
// function as used for the JTAG data register (DR) which requires MSB 
// first.
//----------------------------------------------------------------------------

// Instructions for the JTAG control signal register
//! \brief Set the JTAG control signal register
#define IR_CNTRL_SIG_16BIT         0xC8   // original value: 0x13
//! \brief Read out the JTAG control signal register
#define IR_CNTRL_SIG_CAPTURE       0x28   // original value: 0x14
//! \brief Release the CPU from JTAG control
#define IR_CNTRL_SIG_RELEASE       0xA8   // original value: 0x15

// Instructions for the JTAG data register
//! \brief Set the MSP430 MDB to a specific 16-bit value with the next 
//! 16-bit data access 
#define IR_DATA_16BIT              0x82   // original value: 0x41
//! \brief Set the MSP430 MDB to a specific 16-bit value (RAM only)
#define IR_DATA_QUICK              0xC2   // original value: 0x43

// Instructions for the JTAG address register
//! \brief Set the MSP430 MAB to a specific 16-bit value
//! \details Use the 20-bit macro for 430X and 430Xv2 architectures
#define IR_ADDR_16BIT              0xC1   // original value: 0x83
//! \brief Read out the MAB data on the next 16/20-bit data access
#define IR_ADDR_CAPTURE            0x21   // original value: 0x84
//! \brief Set the MSP430 MDB with a specific 16-bit value and write
//! it to the memory address which is currently on the MAB
#define IR_DATA_TO_ADDR            0xA1   // original value: 0x85
//! \brief Bypass instruction - TDI input is shifted to TDO as an output
#define IR_BYPASS                  0xFF   // original value: 0xFF
#define IR_DATA_CAPTURE            0x42

//! \brief JTAG identification value for 430Xv2 architecture FR4XX/FR2xx devices
#define JTAG_ID98                  0x98

// Constants for runoff status
//! \brief return 0 = error
#define STATUS_ERROR     0      // false
//! \brief return 1 = no error
#define STATUS_OK        1      // true

//! \brief Holds the value of TDO-bit
bool tdo_bit = false;
//! \brief Holds the last value of TCLK before entering a JTAG sequence
bool TCLK_saved = true;

bool TSTRead() {
    return P1IN & BIT4;
}

bool RSTRead() {
    return P1IN & BIT5;
}

void TSTWrite(bool x) {
    if (x)  P1OUT   |=  BIT4;
    else    P1OUT   &= ~BIT4;
}

void RSTWrite(bool x) {
    if (x)  P1OUT   |=  BIT5;
    else    P1OUT   &= ~BIT5;
}

void TSTDir(bool out) {
    if (out)    P1DIR   |=  BIT4;
    else        P1DIR   &= ~BIT4;
}

void RSTDir(bool out) {
    if (out)    P1DIR   |=  BIT5;
    else        P1DIR   &= ~BIT5;
}

#define TCKRead     TSTRead
#define TDIORead    RSTRead
#define TCKWrite    TSTWrite
#define TDIOWrite   RSTWrite
#define TCKDir      TSTDir
#define TDIODir     RSTDir


#define CPUFreqMHz 16
#define DelayUs(us) __delay_cycles(CPUFreqMHz*us);

void DelayMs(uint32_t ms) {
    for (volatile uint32_t i=0; i<ms; i++) {
        DelayUs(1000);
    }
}







//! \brief Delay function as a transition between SBW time slots
void nNOPS() {
    DelayUs(1);
}

//! \brief SBW macro: set TMS signal
void TMSH() {
    TDIOWrite(1);
    nNOPS();
    TCKWrite(0);
    nNOPS();
    TCKWrite(1);
}
//! \brief SBW macro: clear TMS signal
void TMSL() {
    TDIOWrite(0);
    nNOPS();
    TCKWrite(0);
    nNOPS();
    TCKWrite(1);
}

//! \brief SBW macro: Set TDI = 1
void TDIH() {
    TDIOWrite(1);
    nNOPS();
    TCKWrite(0);
    nNOPS();
    TCKWrite(1);
}
//! \brief SBW macro: clear TDI signal
void TDIL() {
    TDIOWrite(0);
    nNOPS();
    TCKWrite(0);
    nNOPS();
    TCKWrite(1);
}
//! \brief SBW macro: TDO cycle without reading TDO
void TDOsbw() {
    TDIODir(0);
    nNOPS();
    TCKWrite(0);
    nNOPS();
    TCKWrite(1);
    TDIODir(1);
}
//! \brief SBW macro: TDO cycle with TDO read
void TDO_RD() {
    TDIODir(0);
    nNOPS();
    TCKWrite(0);
    nNOPS();
    tdo_bit = TDIORead();
    TCKWrite(1);
    TDIODir(1);
}


//  combinations of sbw-cycles (TMS, TDI, TDO)
//---------------------------------
void TMSL_TDIL(void)
{
    TMSL();
    TDIL();
    TDOsbw();
}
//---------------------------------
void TMSH_TDIL(void)
{
    TMSH();
    TDIL();
    TDOsbw();
}
//------------------------------------
void TMSL_TDIH(void)
{
    TMSL();
    TDIH();
    TDOsbw();
}
//-------------------------------------
void TMSH_TDIH(void)
{
    TMSH();
    TDIH();
    TDOsbw();
}
//------------------------------------
void TMSL_TDIH_TDOrd(void)
{
    TMSL();
    TDIH();
    TDO_RD();
}
//------------------------------------
void TMSL_TDIL_TDOrd(void)
{
    TMSL();
    TDIL();
    TDO_RD();
}
//------------------------------------
void TMSH_TDIH_TDOrd(void)
{
    TMSH();
    TDIH();
    TDO_RD();
}
//------------------------------------
void TMSH_TDIL_TDOrd(void)
{
    TMSH();
    TDIL();
    TDO_RD();
}

//----------------------------------------------------------------------------
//! \brief Function to set up the JTAG pins
void ConnectJTAG()
{
    // drive JTAG/TEST signals
    TSTDir(0);
    RSTDir(0);
    TSTWrite(0);
    RSTWrite(0);
    TSTDir(1);
    RSTDir(1);
    DelayMs(15);
}

//----------------------------------------------------------------------------
//! \brief Function to stop the JTAG communication by releasing the JTAG signals
void StopJtag()
{
    // release JTAG/TEST signals
    TSTDir(0);
    RSTDir(0);
    DelayMs(15);
}

//----------------------------------------------------------------------------
//! \brief Shift a value into TDI (MSB first) and simultaneously shift out a 
//! value from TDO (MSB first).
//! \param Format (number of bits shifted, 8 (F_BYTE), 16 (F_WORD), 
//! 20 (F_ADDR) or 32 (F_LONG))
//! \param Data (data to be shifted into TDI)
//! \return unsigned long (scanned TDO value)
unsigned long AllShifts(uint16_t Format, unsigned long Data)
{
   unsigned long TDOword = 0x00000000;
   unsigned long MSB = 0x00000000;
   uint16_t i;

   switch(Format)
   {
   case F_BYTE: MSB = 0x00000080;
     break;
   case F_WORD: MSB = 0x00008000;
     break;
   case F_ADDR: MSB = 0x00080000;
     break;
   case F_LONG: MSB = 0x80000000;
     break;
   default: // this is an unsupported format, function will just return 0
     return TDOword;
   }
   // shift in bits
   for (i=Format; i>0; i--)
   {
        if (i == 1)
        {
          ((Data & MSB) == 0) ? TMSH_TDIL_TDOrd() : TMSH_TDIH_TDOrd();
        }
        else
        {
          ((Data & MSB) == 0) ? TMSL_TDIL_TDOrd() : TMSL_TDIH_TDOrd();
        }
        Data <<= 1;
        if (tdo_bit)
            TDOword++;
        if (i > 1)
            TDOword <<= 1;
   }
   TMSH_TDIH();
   if (TCLK_saved)
   {
        TMSL_TDIH();
   }
   else
   {
        TMSL_TDIL();
   }

   // de-scramble bits on a 20bit shift
   if(Format == F_ADDR)
   {
     TDOword = ((TDOword << 16) + (TDOword >> 4)) & 0x000FFFFF;
   }
   
   return(TDOword);
}



//----------------------------------------------------------------------------
//! \brief Reset target JTAG interface and perform fuse-HW check.
void ResetTAP(void)
{
    uint16_t i;
    // Reset JTAG FSM
    for (i=6; i>0; i--)
    {
        TMSH_TDIH();
    }
    // JTAG FSM is now in Test-Logic-Reset
    TMSL_TDIH();
    // now in Run/Test Idle
}


//----------------------------------------------------------------------------
//! \brief Function for shifting a new instruction into the JTAG instruction
//! register through TDI (MSB first, but with interchanged MSB - LSB, to
//! simply use the same shifting function, Shift(), as used in DR_Shift16).
//! \param[in] byte Instruction (8bit JTAG instruction, MSB first)
//! \return word TDOword (value shifted out from TDO = JTAG ID)
uint16_t IR_Shift(uint8_t instruction)
{
    // JTAG FSM state = Run-Test/Idle
    if (TCLK_saved)
    {
        TMSH_TDIH();
    }
    else
    {
        TMSH_TDIL();
    }
    // JTAG FSM state = Select DR-Scan
    TMSH_TDIH();

    // JTAG FSM state = Select IR-Scan
    TMSL_TDIH();
    // JTAG FSM state = Capture-IR
    TMSL_TDIH();
    // JTAG FSM state = Shift-IR, Shift in TDI (8-bit)
    return(AllShifts(F_BYTE, instruction));
    // JTAG FSM state = Run-Test/Idle
}


//----------------------------------------------------------------------------
//! \brief Function to start the JTAG communication - RST line high - device starts
//! code execution   
void EntrySequences_RstHigh_SBW()
{
    TSTWrite(0);
    DelayMs(4);

    RSTWrite(1);
    
    TSTWrite(1);
    DelayMs(20);

    // phase 1
    RSTWrite(1);
    DelayUs(60);

    // phase 2 -> TEST pin to 0, no change on RST pin
    // for Spy-Bi-Wire
    TSTWrite(0);
    // phase 3
    DelayUs(1);
    // phase 4 -> TEST pin to 1, no change on RST pin
    // for Spy-Bi-Wire
    TSTWrite(1);
    DelayUs(60);

    // phase 5
    DelayMs(5);
}

//----------------------------------------------------------------------------
//! \brief Function to determine & compare core identification info 
//! \return word (STATUS_OK if correct JTAG ID was returned, STATUS_ERROR 
//! otherwise)
uint16_t GetJTAGID() {
    uint16_t jid = 0;
    for (int i=0; i < MAX_ENTRY_TRY; i++)
    {
        // release JTAG/TEST signals to safely reset the test logic
        StopJtag();
        // establish the physical connection to the JTAG interface
        ConnectJTAG();
        // Apply again 4wire/SBW entry Sequence. 
        // set ResetPin =1    
        EntrySequences_RstHigh_SBW();
        // reset TAP state machine -> Run-Test/Idle
        ResetTAP();
        // shift out JTAG ID
        jid = (uint16_t)IR_Shift(IR_CNTRL_SIG_CAPTURE);
         
        // break if a valid JTAG ID is being returned
        if(jid == JTAG_ID98)
        {
            return jid;
        }
    }
    return STATUS_ERROR;
}

#pragma once
#include <msp430g2553.h>
#include <stddef.h>
#include <type_traits>
#include "GPIO.h"

template <typename GPIOT, typename GPIOR>
class MSP430 {
private:
    using TMS = bool;
    static constexpr TMS TMS0 = false;
    static constexpr TMS TMS1 = true;
    static constexpr TMS TMSX = false; // Don't care
    
    using TDI = bool;
    static constexpr TDI TDI0 = false;
    static constexpr TDI TDI1 = true;
    static constexpr TDI TDIX = false; // Don't care
    
    using TDO = bool;
    static constexpr TDO TDO0 = false;
    static constexpr TDO TDO1 = true;
    static constexpr TDO TDOX = false; // Don't care
    
    #define CPUFreqMHz 16
    #define _delayUs(us) __delay_cycles(CPUFreqMHz*us);
    
    void _delayMs(uint32_t ms) {
        for (volatile uint32_t i=0; i<ms; i++) {
            _delayUs(1000);
        }
    }
    
    GPIOT& _test;
    GPIOR& _rst_;
    #define _tck _test
    #define _tdio _rst_
    
public:
    MSP430(GPIOT& test, GPIOR& rst_) :
    _test(test), _rst_(rst_)
    {}
    
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
    #define IR_CNTRL_SIG_16BIT         0x13
    //! \brief Read out the JTAG control signal register
    #define IR_CNTRL_SIG_CAPTURE       0x14
    //! \brief Release the CPU from JTAG control
    #define IR_CNTRL_SIG_RELEASE       0x15
    
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
    
    void _startShiftIR() {
        // <-- Run-Test/Idle
        _sbwio(TMS1, TDIX);
        // <-- Select DR-Scan
        _sbwio(TMS1, TDIX);
        // <-- Select IR-Scan
        _sbwio(TMS0, TDIX);
        // <-- Capture-IR
        _sbwio(TMS0, TDIX);
        // <-- Shift-IR
    }
    
    void _startShiftDR() {
        // <-- Run-Test/Idle
        _sbwio(TMS1, TDIX);
        // <-- Select DR-Scan
        _sbwio(TMS0, TDIX);
        // <-- Capture-IR
        _sbwio(TMS0, TDIX);
        // <-- Shift-DR
    }
    
    // Perform a single Spy-bi-wire I/O cycle
    TDO _sbwio(TMS tms, TDI tdi) {
        // ## Write TMS
        {
            _tdio.write(tms);
            _delayUs(1);
            
            _tck.write(0);
            _delayUs(1);
            _tck.write(1);
            _delayUs(1);
        }
        
        // ## Write TDI
        {
            _tdio.write(tdi);
            _delayUs(1);
            
            _tck.write(0);
            _delayUs(1);
            _tck.write(1);
            // Stop driving SBWTDIO, in preparation for the slave to start driving it
            _tdio.config(0);
            _delayUs(1);
        }
        
        // ## Read TDO
        TDO tdo = TDO0;
        {
            _tck.write(0);
            _delayUs(1);
            // Read the TDO value, driven by the slave, while SBWTCK=0
            tdo = _tdio.read();
            _tck.write(1);
            
            _delayUs(1);
            // Start driving SBWTDIO again
            _tdio.config(1);
        }
        
        return tdo;
    }
    
    
    
    
    
    //! \brief SBW macro: set TMS signal
    void TMSH() {
        _tdio.write(1);
        _delayUs(1);
        _tck.write(0);
        _delayUs(1);
        _tck.write(1);
    }
    
    //! \brief SBW macro: clear TMS signal
    void TMSL() {
        _tdio.write(0);
        _delayUs(1);
        _tck.write(0);
        _delayUs(1);
        _tck.write(1);
    }

    //! \brief SBW macro: Set TDI = 1
    void TDIH() {
        _tdio.write(1);
        _delayUs(1);
        _tck.write(0);
        _delayUs(1);
        _tck.write(1);
    }
    //! \brief SBW macro: clear TDI signal
    void TDIL() {
        _tdio.write(0);
        _delayUs(1);
        _tck.write(0);
        _delayUs(1);
        _tck.write(1);
    }
    //! \brief SBW macro: TDO cycle without reading TDO
    void TDOsbw() {
        _tdio.config(0);
        _delayUs(1);
        _tck.write(0);
        _delayUs(1);
        _tck.write(1);
        _tdio.config(1);
    }
    //! \brief SBW macro: TDO cycle with TDO read
    void TDO_RD() {
        _tdio.config(0);
        _delayUs(1);
        _tck.write(0);
        _delayUs(1);
        tdo_bit = _tdio.read();
        _tck.write(1);
        _tdio.config(1);
    }


    //  combinations of sbw-cycles (TMS, TDI, TDO)
    //---------------------------------
    void TMSL_TDIL()
    {
        TMSL();
        TDIL();
        TDOsbw();
    }
    //---------------------------------
    void TMSH_TDIL()
    {
        TMSH();
        TDIL();
        TDOsbw();
    }
    //------------------------------------
    void TMSL_TDIH()
    {
        TMSL();
        TDIH();
        TDOsbw();
    }
    //-------------------------------------
    void TMSH_TDIH()
    {
        TMSH();
        TDIH();
        TDOsbw();
    }
    //------------------------------------
    void TMSL_TDIH_TDOrd()
    {
        TMSL();
        TDIH();
        TDO_RD();
    }
    //------------------------------------
    void TMSL_TDIL_TDOrd()
    {
        TMSL();
        TDIL();
        TDO_RD();
    }
    //------------------------------------
    void TMSH_TDIH_TDOrd()
    {
        TMSH();
        TDIH();
        TDO_RD();
    }
    //------------------------------------
    void TMSH_TDIL_TDOrd()
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
        _test.config(0);
        _rst_.config(0);
        _test.write(0);
        _rst_.write(0);
        _test.config(1);
        _rst_.config(1);
        _delayMs(15);
    }

    //----------------------------------------------------------------------------
    //! \brief Function to stop the JTAG communication by releasing the JTAG signals
    void StopJtag()
    {
        // release JTAG/TEST signals
        _test.config(0);
        _rst_.config(0);
        _delayMs(15);
    }
    
    // Using std::common_type here to prevent auto type deduction,
    // thus requiring `T` to be explicit
    template <typename T>
    T _shift(typename std::common_type<T>::type dout) {
        // <-- Shift-DR / Shift-IR
        T din = 0;
        for (size_t i=0; i<sizeof(T)*8; i++) {
            const TMS tms = (i<((sizeof(T)*8)-1) ? TMS0 : TMS1); // Final bit needs TMS=1
            din <<= 1;
            din |= _sbwio(tms, dout&0x1);
            dout >>= 1;
        }
        
        // <-- Exit1-DR / Exit1-IR
        _sbwio(TMS1, TDOX);
        // <-- Update-DR / Update-IR
        _sbwio(TMS0, TDOX);
        // <-- Run-Test/Idle
        
        return din;
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
    void ResetTAP() {
        // Reset JTAG FSM
        for (int i=0; i<6; i++) {
            _sbwio(TMS1, TDI1);
        }
        // JTAG FSM is now in Test-Logic-Reset
        _sbwio(TMS0, TDI1);
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
        _test.write(0);
        _delayMs(4);

        _rst_.write(1);
        
        _test.write(1);
        _delayMs(20);

        // phase 1
        _rst_.write(1);
        _delayUs(60);

        // phase 2 -> TEST pin to 0, no change on RST pin
        // for Spy-Bi-Wire
        _test.write(0);
        // phase 3
        _delayUs(1);
        // phase 4 -> TEST pin to 1, no change on RST pin
        // for Spy-Bi-Wire
        _test.write(1);
        _delayUs(60);

        // phase 5
        _delayMs(5);
    }

    //----------------------------------------------------------------------------
    //! \brief Function to determine & compare core identification info 
    //! \return word (STATUS_OK if correct JTAG ID was returned, STATUS_ERROR 
    //! otherwise)
    uint16_t GetJTAGID() {
        for (int i=0; i < MAX_ENTRY_TRY; i++) {
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
            
            _startShiftIR();
            const uint16_t jid = _shift<uint8_t>(IR_CNTRL_SIG_CAPTURE);
            if (jid == JTAG_ID98) {
                return jid;
            }
        }
        return STATUS_ERROR;
    }
    
//    void go() {
//        _irq.disable();
//        
//        #define IR_CNTRL_SIG_16BIT	    0xC8	/* 0x13 */
//        #define IR_CNTRL_SIG_CAPTURE	0x28	/* 0x14 */
//        #define IR_JMB_EXCHANGE         0x86    /* 0x61 */
////        #define IR_CNTRL_SIG_16BIT	0x13
////        #define IR_CNTRL_SIG_CAPTURE	0x14
//        
//        // ## JTAG entry, attempt 1
//        {
//            // ## Reset pin states
//            {
//                _mspTest.write(0);
//                _mspRst_.write(1);
//                for (uint32_t i=0; i<65535; i++) {
//                    _sbwDelay();
//                }
//            }
//            
//            // ## Reset the MSP430 so that it starts from a known state
//            {
//                _mspRst_.write(0);
//                _sbwDelay();
//                _mspRst_.write(1);
//                _sbwDelay();
//            }
//            
//            // ## Enable SBW interface
//            {
//                // Assert TEST
//                _mspTest.write(1);
//                _sbwDelay();
//            }
//            
//            // ## Choose 2-wire/Spy-bi-wire mode
//            {
//                // SBWTDIO=1, and apply a single clock to SBWTCK
//                _tdio.write(1);
//                _sbwDelay();
//                _tck.write(0);
//                _sbwDelay();
//                _tck.write(1);
//                _sbwDelay();
//            }
//
//            // ## Reset JTAG state machine
//            {
//                // TMS=1 for 6 clocks
//                for (int i=0; i<100; i++) {
//                    _sbwio(TMS1, TDIX);
//                }
//                // <-- Test-Logic-Reset
//                
//                // TMS=0 for 1 clock
//                _sbwio(TMS0, TDIX);
//                // <-- Run-Test/Idle
//                
//                // Fuse check: toggle TMS twice
//                _sbwio(TMS1, TDIX);
//                // <-- Select DR-Scan
//                _sbwio(TMS0, TDIX);
//                // <-- Capture DR
//                _sbwio(TMS1, TDIX);
//                // <-- Exit1-DR
//                _sbwio(TMS0, TDIX);
//                // <-- Pause-DR
//                _sbwio(TMS1, TDIX);
//                // <-- Exit2-DR
//                
//                // In SBW mode, the fuse check causes the JTAG state machine to change states,
//                // so we need to explicitly return to the Run-Test/Idle state.
//                // (This isn't necessary in 4-wire JTAG mode, since the state machine doesn't
//                // change states when performing the fuse check.)
//                _sbwio(TMS1, TDIX);
//                // <-- Update-DR
//                _sbwio(TMS0, TDIX);
//                // <-- Run-Test/Idle
//            }
//            
//            // Try to read JTAG ID
//            {
//                _startShiftIR();
//                _shift<uint8_t>(IR_CNTRL_SIG_16BIT);
//                
//                _startShiftDR();
//                _shift<uint16_t>(0x2401);
//                
//                volatile uint8_t jtagID = _shift<uint8_t>(IR_CNTRL_SIG_CAPTURE);
//                for (;;);
//            }
//        }
//        
//        // ## JTAG entry, attempt 2
//        {
//            // ## Reset pin states
//            {
//                _mspTest.write(0);
//                _mspRst_.write(1);
//                for (uint32_t i=0; i<65535; i++) {
//                    _sbwDelay();
//                }
//            }
//            
//            // ## Reset the MSP430 so that it starts from a known state
//            {
//                _mspRst_.write(0);
//                _sbwDelay();
//            }
//            
//            // ## Enable SBW interface
//            {
//                // Assert TEST
//                _mspTest.write(1);
//                _sbwDelay();
//            }
//            
//            // ## Choose 2-wire/Spy-bi-wire mode
//            {
//                // SBWTDIO=1, and apply a single clock to SBWTCK
//                _tdio.write(1);
//                _sbwDelay();
//                _tck.write(0);
//                _sbwDelay();
//                _tck.write(1);
//                _sbwDelay();
//            }
//            
//            // ## Reset JTAG state machine
//            {
//                // TMS=1 for 6 clocks
//                for (int i=0; i<100; i++) {
//                    _sbwio(TMS1, TDIX);
//                }
//                // <-- Test-Logic-Reset
//                
//                // TMS=0 for 1 clock
//                _sbwio(TMS0, TDIX);
//                // <-- Run-Test/Idle
//                
//                // Fuse check: toggle TMS twice
//                _sbwio(TMS1, TDIX);
//                // <-- Select DR-Scan
//                _sbwio(TMS0, TDIX);
//                // <-- Capture DR
//                _sbwio(TMS1, TDIX);
//                // <-- Exit1-DR
//                _sbwio(TMS0, TDIX);
//                // <-- Pause-DR
//                _sbwio(TMS1, TDIX);
//                // <-- Exit2-DR
//                
//                // In SBW mode, the fuse check causes the JTAG state machine to change states,
//                // so we need to explicitly return to the Run-Test/Idle state.
//                // (This isn't necessary in 4-wire JTAG mode, since the state machine doesn't
//                // change states when performing the fuse check.)
//                _sbwio(TMS1, TDIX);
//                // <-- Update-DR
//                _sbwio(TMS0, TDIX);
//                // <-- Run-Test/Idle
//            }
//            
//            {
//                _startShiftIR();
//                _shift<uint8_t>(IR_JMB_EXCHANGE);
//                
//                _startShiftDR();
//                _shift<uint16_t>(0xA55A);
//            }
//            
//            // ## Reset the MSP430 so that it starts from a known state
//            {
//                _mspRst_.write(1);
//                _sbwDelay();
//            }
//        }
//        
//        _irq.restore();
//    }
};

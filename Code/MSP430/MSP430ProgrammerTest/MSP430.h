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
    
    void _tapReset() {
        // ## Reset JTAG state machine
        {
            // TMS=1 for 6 clocks
            for (int i=0; i<6; i++) {
                _sbwio(TMS1, TDIX);
            }
            // <-- Test-Logic-Reset
            
            // TMS=0 for 1 clock
            _sbwio(TMS0, TDIX);
            // <-- Run-Test/Idle
        }
    }
    
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
    
    uint16_t GetJTAGID() {
        for (int i=0; i<10; i++) {
            // ## Reset pin states
            {
                _test.write(0);
                _rst_.write(1);
                _delayMs(10);
            }
            
            // ## Reset the MSP430 so that it starts from a known state
            {
                _rst_.write(0);
                _delayUs(1);
            }
            
            // ## Enable test mode
            {
                // RST=1
                _rst_.write(1);
                _delayUs(1);
                // Assert TEST
                _test.write(1);
                _delayUs(1);
            }
            
            // ## Choose 2-wire/Spy-bi-wire mode
            {
                // TDIO=1 while applying a single clock to TCK
                _tdio.write(1);
                
                _delayUs(1);
                _tck.write(0);
                _delayUs(1);
                _tck.write(1);
                _delayUs(1);
            }
            
            // ## Reset JTAG state machine (test access port, TAP)
            {
                _tapReset();
            }
            
            // ## 
            {
                _startShiftIR();
                const uint16_t jid = _shift<uint8_t>(IR_CNTRL_SIG_CAPTURE);
                if (jid == JTAG_ID98) {
                    return jid;
                }
            }
        }
        return 0;
    }
};

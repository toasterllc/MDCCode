#pragma once
#include <msp430g2553.h>
#include <stddef.h>
#include <type_traits>
#include "GPIO.h"

template <typename GPIOT, typename GPIOR>
class MSP430 {
private:
    static constexpr uint8_t TMS0 = false;
    static constexpr uint8_t TMS1 = true;
    static constexpr uint8_t TMSX = false; // Don't care
    
    static constexpr uint8_t TDI0 = false;
    static constexpr uint8_t TDI1 = true;
    static constexpr uint8_t TDIX = false; // Don't care
    
    static constexpr uint8_t TDO0 = false;
    static constexpr uint8_t TDO1 = true;
    static constexpr uint8_t TDOX = false; // Don't care
    
    static constexpr uint8_t IR_CNTRL_SIG_16BIT     = 0x13;
    static constexpr uint8_t IR_CNTRL_SIG_CAPTURE   = 0x14;
    static constexpr uint8_t IR_CNTRL_SIG_RELEASE   = 0x15;
    
    static constexpr uint8_t IR_DATA_16BIT          = 0x41;
    static constexpr uint8_t IR_DATA_QUICK          = 0x43;
    
    static constexpr uint8_t IR_ADDR_16BIT          = 0x83;
    static constexpr uint8_t IR_ADDR_CAPTURE        = 0x84;
    static constexpr uint8_t IR_DATA_TO_ADDR        = 0x85;
    static constexpr uint8_t IR_BYPASS              = 0xFF;
    static constexpr uint8_t IR_DATA_CAPTURE        = 0x42;
    
    static constexpr uint8_t JTAG_ID                = 0x98;
    
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
    uint8_t _sbwio(uint8_t tms, uint8_t tdi) {
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
        uint8_t tdo = TDO0;
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
            const uint8_t tms = (i<((sizeof(T)*8)-1) ? TMS0 : TMS1); // Final bit needs TMS=1
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
    
public:
    MSP430(GPIOT& test, GPIOR& rst_) :
    _test(test), _rst_(rst_)
    {}
    
    uint16_t getJTAGID() {
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
            
            // ## Shift out the JTAG ID
            {
                _startShiftIR();
                const uint16_t jid = _shift<uint8_t>(IR_CNTRL_SIG_CAPTURE);
                if (jid == JTAG_ID) {
                    return jid;
                }
            }
        }
        return 0;
    }
};

#pragma once
#include <msp430g2553.h>
#include <stddef.h>
#include <type_traits>
#include "GPIO.h"
#include "printf.h"

template <typename GPIOT, typename GPIOR>
class MSP430 {
private:
    using TMS = bool;
    static constexpr TMS TMS0 = 0;
    static constexpr TMS TMS1 = 1;
    static constexpr TMS TMSX = 0; // Don't care
    
    using TDI = bool;
    static constexpr TDI TDI0 = 0;
    static constexpr TDI TDI1 = 1;
    static constexpr TDI TDIX = 0; // Don't care
    
    using TDO = bool;
    static constexpr TDO TDO0 = 0;
    static constexpr TDO TDO1 = 1;
    static constexpr TDO TDOX = 0; // Don't care
    
    using TCLK = bool;
    static constexpr TCLK TCLK0 = 0;
    static constexpr TCLK TCLK1 = 1;
    static constexpr TCLK TCLKX = 0; // Don't care
    
    static constexpr uint8_t IR_CNTRL_SIG_16BIT     = 0x13;
    static constexpr uint8_t IR_CNTRL_SIG_CAPTURE   = 0x14;
    static constexpr uint8_t IR_CNTRL_SIG_RELEASE   = 0x15;
    
    static constexpr uint8_t IR_COREIP_ID           = 0x17;
    
    static constexpr uint8_t IR_DATA_16BIT          = 0x41;
    static constexpr uint8_t IR_DATA_QUICK          = 0x43;
    
    static constexpr uint8_t IR_ADDR_16BIT          = 0x83;
    static constexpr uint8_t IR_ADDR_CAPTURE        = 0x84;
    static constexpr uint8_t IR_DATA_TO_ADDR        = 0x85;
    static constexpr uint8_t IR_DEVICE_ID           = 0x87;
    static constexpr uint8_t IR_BYPASS              = 0xFF;
    static constexpr uint8_t IR_DATA_CAPTURE        = 0x42;
    
    static constexpr uint8_t JTAGID                 = 0x98;
    
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
    
    TCLK _tclkSaved = TCLK1;
    
    void _tapReset() {
        // ## Reset JTAG state machine
        // TMS=1 for 6 clocks
        for (int i=0; i<6; i++) {
            _sbwio(TMS1, TDIX);
        }
        // <-- Test-Logic-Reset
        
        // TMS=0 for 1 clock
        _sbwio(TMS0, TDIX);
        // <-- Run-Test/Idle
    }
    
    void _startShiftIR() {
        // <-- Run-Test/Idle
        _sbwio(TMS1, _tclkSaved);
        // <-- Select DR-Scan
        _sbwio(TMS1, TDI1);
        // <-- Select IR-Scan
        _sbwio(TMS0, TDI1);
        // <-- Capture-IR
        _sbwio(TMS0, TDI1);
        // <-- Shift-IR
    }
    
    void _startShiftDR() {
        // <-- Run-Test/Idle
        _sbwio(TMS1, _tclkSaved);
        // <-- Select DR-Scan
        _sbwio(TMS0, TDI1);
        // <-- Capture-IR
        _sbwio(TMS0, TDI1);
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
    
    enum class ShiftType : uint8_t {
        Byte    = 8,
        Word    = 16,
        Addr    = 20,
    };
    
    // Using std::common_type here to prevent auto type deduction,
    // because we want `T` to be explicit.
    template <ShiftType T>
    uint32_t _shift(uint32_t dout) {
        // <-- Shift-DR / Shift-IR
        uint32_t din = 0;
        for (size_t i=0; i<(uint8_t)T; i++) {
            const uint8_t tms = (i<((uint8_t)T-1) ? TMS0 : TMS1); // Final bit needs TMS=1
            din <<= 1;
            din |= _sbwio(tms, dout&0x1);
            dout >>= 1;
        }
        
        // <-- Exit1-DR / Exit1-IR
        _sbwio(TMS1, TDOX);
        // <-- Update-DR / Update-IR
        _sbwio(TMS0, TDOX);
        // <-- Run-Test/Idle
        
        if constexpr (T == ShiftType::Addr) {
            din = ((din&0xF)<<16) | (din>>4);
        }
        
        return din;
    }
    
    template <ShiftType T>
    uint32_t _shiftIR(uint32_t d) {
        _startShiftIR();
        return _shift<T>(d);
    }
    
    template <ShiftType T>
    uint32_t _shiftDR(uint32_t d) {
        _startShiftDR();
        return _shift<T>(d);
    }
    
    uint8_t _readJTAGID() {
        return _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_CAPTURE);
    }
    
    bool _readJTAGFuseBlown() {
        _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_CAPTURE);
        const uint16_t status = _shiftDR<ShiftType::Word>(0xAAAA);
//        printf("JTAG fuse status: %x\r\n", status);
        return status == 0x5555;
    }
    
    uint32_t _readCoreID() {
        _shiftIR<ShiftType::Byte>(IR_COREIP_ID);
        return _shiftDR<ShiftType::Word>(0);
    }
    
    uint32_t _readDeviceIDAddr() {
        _shiftIR<ShiftType::Byte>(IR_DEVICE_ID);
        return _shiftDR<ShiftType::Addr>(0);
    }
    
    void _tclkSet(TCLK x) {
        // ## Write TMS
        {
            _tdio.write(0);
            _delayUs(1);
            
            _tck.write(0);
            _delayUs(1);
            
            // Restore saved value of TCLK during TCK=0 period
            _tdio.write(_tclkSaved);
            
            _tck.write(1);
            _delayUs(1);
        }
        
        // ## Write TDI=TCLK
        {
            _tdio.write(x);
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
        
        
        
        _sbwio(TMS0, x);
        _tclkSaved = x;
    }
    
    void _tclkCycle() {
        _tclkSet(0);
        _tclkSet(1);
    }
    
    // Using std::common_type here to prevent auto type deduction,
    // because we want `T` to be explicit.
    template <typename T>
    void _writeMem(uint32_t addr, typename std::common_type<T>::type data) {
        _tclkSet(0);
        _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_16BIT);
        if constexpr (std::is_same_v<T, uint8_t>) {
            _shiftDR<ShiftType::Word>(0x0510);
        } else if constexpr (std::is_same_v<T, uint16_t>) {
            _shiftDR<ShiftType::Word>(0x0500);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        
        _shiftIR<ShiftType::Byte>(IR_ADDR_16BIT);
        _shiftDR<ShiftType::Addr>(addr);
        _tclkSet(1);
        
        // Only apply data during clock high phase
        _shiftIR<ShiftType::Byte>(IR_DATA_TO_ADDR);
        _shiftDR<ShiftType::Word>(data);           // Shift in 16 bits
        _tclkSet(0);
        _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_16BIT);
        _shiftDR<ShiftType::Word>(0x0501);
        _tclkSet(1);
        // One or more cycle, so CPU is driving correct MAB
        _tclkSet(0);
        _tclkSet(1);
        // Processor is now again in Init State
    }
    
    bool _resetCPU() {
        // One clock to empty the pipe
        _tclkCycle();
        
        // Prepare access to the JTAG CNTRL SIG register
        _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_16BIT);
        // Release CPUSUSP signal and apply POR signal
        _shiftIR<ShiftType::Word>(0x0C01);
        // Release POR signal again
        _shiftIR<ShiftType::Word>(0x0401);
        
        // Set PC to 'safe' memory location
        _shiftIR<ShiftType::Byte>(IR_DATA_16BIT);
        _tclkCycle();
        _tclkCycle();
        _shiftIR<ShiftType::Word>(0x0004);
        // PC is set to 0x4 - MAB value can be 0x6 or 0x8
        
        // Drive safe address into PC
        _tclkCycle();
        _shiftIR<ShiftType::Byte>(IR_DATA_CAPTURE); // TODO: is this necessary?
        
        // Two more clocks to release CPU internal POR delay signals
        _tclkCycle();
        _tclkCycle();
        
        // Set CPUSUSP signal again
        _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_16BIT);
        _shiftIR<ShiftType::Word>(0x0501);
        // One more clock
        _tclkCycle();
        // <- CPU in 'Full-Emulation-State'
        
        // Disable Watchdog Timer on target device now by setting the HOLD signal
        // in the WDT_CNTRL register
        _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_CAPTURE); // TODO: is this necessary?
        _writeMem<uint16_t>(0x01CC, 0x5A80);
        
        // Check if device is in Full-Emulation-State again and return status
        _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_CAPTURE);
        if (!(_shiftIR<ShiftType::Word>(0) & 0x0301)) {
            return false;
        }
        
        return true;
    }
    
    template <class...> static std::false_type _AlwaysFalse;
    
public:
    MSP430(GPIOT& test, GPIOR& rst_) :
    _test(test), _rst_(rst_)
    {}
    
    bool connect() {
        for (int i=0; i<3; i++) {
//            printf("Attempt %i\r\n", i);
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
            
            // ## Validate the JTAG ID
            {
                if (_readJTAGID() != JTAGID) {
                    printf("JTAG ID bad\r\n");
                    continue; // Try again
                }
            }
            
            // ## Check JTAG fuse blown state
            {
                if (_readJTAGFuseBlown()) {
                    printf("JTAG fuse blown\r\n");
                    continue; // Try again
                }
            }
            
            // ## Validate the Core ID
            {
                if (_readCoreID() == 0) {
                    printf("Core ID BAD\r\n");
                    continue; // Try again
                }
            }
            
            // ## Validate the Device ID
            {
                // Set device into JTAG mode + read
                {
                    _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_16BIT);
                    _shiftDR<ShiftType::Word>(0x1501);
                }
                
                // Wait until CPU is sync'd
                {
                    bool sync = false;
                    for (int i=0; i<3 && !sync; i++) {
                        _shiftIR<ShiftType::Byte>(IR_CNTRL_SIG_CAPTURE);
                        const uint16_t cpuStatus = _shiftDR<ShiftType::Word>(0) & 0x0200;
                        printf("CPU status: %x\r\n", cpuStatus);
                        sync = cpuStatus & 0x0200;
                    }
                    if (!sync) {
                        printf("Failed to sync CPU\r\n");
                        continue; // Try again
                    }
                }
                
                // Reset CPU
                {
                    if (!_resetCPU()) {
                        printf("Reset CPU failed\r\n");
                        continue;  // Try again
                    }
                }
                
                // Read device ID
                {
                    const uint32_t deviceIDAddr = _readDeviceIDAddr();
                }
            }
            
            // Nothing failed!
            return true;
        }
        
        // Too many failures
        return false;
    }
    
    bool read(uint32_t src, uint8_t* dst, uint32_t len) {
        
    }
    
};

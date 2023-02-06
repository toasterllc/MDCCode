#pragma once
#include <string.h>
#include <type_traits>
#include "GPIO.h"
#include "Toastbox/Scheduler.h"

template <typename T_TestPin, typename T_RstPin_, uint8_t T_CPUFreqMHz>
class MSP430JTAG {
public:
    struct Pin {
        using Test = typename T_TestPin::template Opts<GPIO::Option::Output0>;
        using Rst_ = typename T_RstPin_::template Opts<GPIO::Option::Output1>;
    };
    
    enum class Status {
        OK,
        Error,
        JTAGDisabled,
    };
    
    static void Init() {
        _PinsReset();
    }
    
    static Status Connect() {
        if (_Connected) return Status::OK; // Short-circuit
        
        for (int i=0; i<3; i++) {
            // Perform JTAG entry sequence with RST_=1
            _JTAGStart(1);
            
            // Reset JTAG state machine (test access port, TAP)
            _TAPReset();
            
            // Validate the JTAG ID
            if (_JTAGIDGet() != _JTAGID) {
                continue; // Try again
            }
            
            // Check JTAG fuse blown state
            if (_JTAGFuseBlown()) {
                return Status::JTAGDisabled;
            }
            
            // Validate the Core ID
            if (_CoreID() == 0) {
                continue; // Try again
            }
            
            // Set device into JTAG mode + read
            _IRShift(_IR_CNTRL_SIG_16BIT);
            _DRShift<16>(0x1501);
            
            // Wait until CPU is sync'd
            if (!_CPUSyncWait()) {
                continue;
            }
            
            // Reset CPU
            if (!_CPUReset()) {
                continue; // Try again
            }
            
            // Validate the Device ID
            {
                const uint16_t deviceID = _DeviceIDGet();
                if (deviceID != _DeviceID) {
                    continue; // Try again
                }
            }
            
            // Disable MPU (so we can write to FRAM)
            if (!_MPUDisable()) {
                continue; // Try again
            }
            
            // Nothing failed!
            _Connected = true;
            return Status::OK;
        }
        
        // Too many failures
        return Status::Error;
    }
    
    static void Disconnect() {
        if (!_Connected) return; // Short-circuit
        _JTAGEnd();
        _Connected = false;
    }
    
    static Status Erase() {
        // Perform JTAG entry sequence with RST_=0
        _JTAGStart(0);
        // Reset JTAG TAP
        _TAPReset();
        
        bool r = _JMBErase();
        if (!r) return Status::Error;
        
        _JTAGEnd();
        return Status::OK;
    }
    
    static uint16_t Read(uint32_t addr) {
        return _Read16(addr);
    }
    
    static void Read(uint32_t addr, void* dst, size_t len) {
        _Read(addr, (uint8_t*)dst, len);
    }
    
    static void Write(uint32_t addr, uint16_t val) {
        _Write16(addr, val);
    }
    
    static void Write(uint32_t addr, const void* src, size_t len) {
        if (_FRAMAddr(addr) && _FRAMAddr(addr+len-1)) {
            // framWrite() is a write implementation that's faster than the
            // general-purpose Write(), but only works for FRAM memory regions
            _FRAMWrite(addr, (uint8_t*)src, len);
        } else {
            _Write(addr, (uint8_t*)src, len);
        }
    }
    
    static void DebugTestSet(bool val) {
        _Test::Write(val);
    }
    
    static void DebugRstSet(bool val) {
        _Rst_::Write(val);
    }
    
    static void DebugTestPulse() {
        Toastbox::IntState ints(false);
        // Write before configuring. If we configured before writing, we could drive the
        // wrong value momentarily before writing the correct value.
        _Test::Write(0);
        _Test::Write(1);
    }
    
    static bool DebugSBWIO(bool tms, bool tclk, bool tdi) {
        return _SBWIO(tms, tclk, tdi);
    }
    
private:
    static constexpr uint8_t _Reverse(uint8_t x) {
        return (x&(1<<7))>>7 | (x&(1<<6))>>5 | (x&(1<<5))>>3 | (x&(1<<4))>>1 |
               (x&(1<<3))<<1 | (x&(1<<2))<<3 | (x&(1<<1))<<5 | (x&(1<<0))<<7 ;
    }
    
    static constexpr uint8_t _IR_CNTRL_SIG_16BIT    = _Reverse(0x13);       // 0xC8
    static constexpr uint8_t _IR_CNTRL_SIG_CAPTURE  = _Reverse(0x14);       // 0x28
    static constexpr uint8_t _IR_CNTRL_SIG_RELEASE  = _Reverse(0x15);       // 0xA8
    static constexpr uint8_t _IR_COREIP_ID          = _Reverse(0x17);       // 0xE8
    
    static constexpr uint8_t _IR_TEST_REG           = _Reverse(0x2A);       // 0x54
    
    static constexpr uint8_t _IR_DATA_16BIT         = _Reverse(0x41);       // 0x82
    static constexpr uint8_t _IR_DATA_CAPTURE       = _Reverse(0x42);       // 0x42
    static constexpr uint8_t _IR_DATA_QUICK         = _Reverse(0x43);       // 0xC2
    static constexpr uint8_t _IR_DATA_PSA           = _Reverse(0x44);       // 0x22
    static constexpr uint8_t _IR_SHIFT_OUT_PSA      = _Reverse(0x46);       // 0x62
    
    static constexpr uint8_t _IR_JMB_EXCHANGE       = _Reverse(0x61);       // 0x86
    
    static constexpr uint8_t _IR_ADDR_16BIT         = _Reverse(0x83);       // 0xC1
    static constexpr uint8_t _IR_ADDR_CAPTURE       = _Reverse(0x84);       // 0x21
    static constexpr uint8_t _IR_DATA_TO_ADDR       = _Reverse(0x85);       // 0xA1
    static constexpr uint8_t _IR_DEVICE_ID          = _Reverse(0x87);       // 0xE1
    
    static constexpr uint8_t _IR_BYPASS             = _Reverse(0xFF);       // 0xFF
    
    static constexpr uint8_t _JTAGID                = 0x98;
//    static constexpr uint16_t _DeviceID             = 0x8311;             // MSP430FR2422
    static constexpr uint16_t _DeviceID             = 0x8240;               // MSP430FR2433
    static constexpr uint32_t _SafePC               = 0x00000004;
    static constexpr uint32_t _SYSRSTIVAddr         = 0x0000015E;
    static constexpr uint32_t _SYSCFG0Addr          = 0x00000160;
    
    static constexpr uint16_t _JMBMailboxIn0Ready   = 0x0001;
    static constexpr uint16_t _JMBMailboxIn1Ready   = 0x0002;
    static constexpr uint16_t _JMBMailboxOut0Ready  = 0x0004;
    static constexpr uint16_t _JMBMailboxOut1Ready  = 0x0008;
    static constexpr uint16_t _JMBDirWrite          = 0x0001; // Direction = writing into mailbox
    static constexpr uint16_t _JMBDirRead           = 0x0004; // Direction = reading from mailbox
    static constexpr uint16_t _JMBWidth32           = 0x0010; // 32-bit operation
    static constexpr uint16_t _JMBMagicNum          = 0xA55A;
    static constexpr uint16_t _JMBEraseCmd          = 0x1A1A;
    
    // _DelayUs: primitive delay implementation
    // Assumes a simple for loop takes 1 clock cycle per iteration
    static void _DelayUs(uint32_t us) {
        const uint32_t cycles = T_CPUFreqMHz*us;
        for (volatile uint32_t i=0; i<cycles; i++);
    }
    
    static constexpr bool _FRAMAddr(uint32_t addr) {
        return addr>=0xE300 && addr<=0xFFFF;
    }
    
    using _Test   = typename Pin::Test;
    using _Rst_   = typename Pin::Rst_;
    using _RstIn_ = typename Pin::Rst_::template Opts<GPIO::Option::Input>;
    
    static inline bool _Connected = false;
    static inline bool _TclkSaved = 1;
    
    static void _PinsReset() {
        // De-assert RST_ before de-asserting TEST, because the MSP430 latches RST_
        // as being asserted, if it's asserted when when TEST is de-asserted
        _Rst_::Write(1);
        _DelayUs(10);
        
        _Test::Write(0);
        _DelayUs(200);
    }
    
    static void _TAPReset() {
        // Reset JTAG state machine
        // TMS=1 for 6 clocks
        for (int i=0; i<6; i++) {
            _SBWIO(1, 1);
        }
        // <- Test-Logic-Reset
        
        // TMS=0 for 1 clock
        _SBWIO(0, 1);
        // <- Run-Test/Idle
    }
    
    static void _IRShiftStart() {
        // <- Run-Test/Idle
        _SBWIO(1, _TclkSaved);
        // <- Select DR-Scan
        _SBWIO(1, 1);
        // <- Select IR-Scan
        _SBWIO(0, 1);
        // <- Capture-IR
        _SBWIO(0, 1);
        // <- Shift-IR
    }
    
    static void _DRShiftStart() {
        // <- Run-Test/Idle
        _SBWIO(1, _TclkSaved);
        // <- Select DR-Scan
        _SBWIO(0, 1);
        // <- Capture-IR
        _SBWIO(0, 1);
        // <- Shift-DR
    }
    
    // Perform a single Spy-bi-wire I/O cycle
    [[gnu::noinline]]
    static bool _SBWIO(bool tms, bool tclk, bool tdi) {
        // We have strict timing requirements, so disable interrupts.
        // Specifically, the low cycle of TCK can't be longer than 7us,
        // otherwise SBW will be disabled.
        Toastbox::IntState ints(false);
        
        // Write TMS
        {
            _Rst_::Write(tms);
            _DelayUs(0);
            
            _Test::Write(0);
            _DelayUs(0);
            
            _Rst_::Write(tclk);
            _Test::Write(1);
            _DelayUs(0);
        }
        
        // Write TDI
        {
            _Rst_::Write(tdi);
            _DelayUs(0);
            
            _Test::Write(0);
            _DelayUs(0);
            
            _Test::Write(1);
            // Stop driving SBWTDIO, in preparation for the slave to start driving it
            _RstIn_::Init();
            _DelayUs(0);
        }
        
        // Read TDO
        bool tdo = 0;
        {
            _Test::Write(0);
            _DelayUs(0);
            // Read the TDO value, driven by the slave, while SBWTCK=0
            tdo = _Rst_::Read();
            _Test::Write(1);
            _DelayUs(0);
            
            // Start driving SBWTDIO again
            _Rst_::Init();
        }
        
        return tdo;
    }
    
    static bool _SBWIO(bool tms, bool tdi) {
        // With no `tclk` specified, use the value for TMS, so that the line stays constant
        // between registering the TMS value and outputting the TDI value
        return _SBWIO(tms, tms, tdi);
    }
    
    // Shifts `dout` MSB first
    template <uint8_t W>
    [[gnu::noinline]]
    static uint32_t _Shift(uint32_t dout) {
        const uint32_t mask = (uint32_t)1<<(W-1);
        // <- Shift-DR / Shift-IR
        uint32_t din = 0;
        for (uint8_t i=0; i<W; i++) {
            const bool tms = (i<(W-1) ? 0 : 1); // Final bit needs TMS=1
            din <<= 1;
            din |= _SBWIO(tms, dout&mask);
            dout <<= 1;
        }
        
        // <- Exit1-DR / Exit1-IR
        _SBWIO(1, 1);
        // <- Update-DR / Update-IR
        _SBWIO(0, _TclkSaved);
        // <- Run-Test/Idle
        
        return din;
    }
    
    static uint8_t _IRShift(uint8_t d) {
        _IRShiftStart();
        const uint8_t din = _Shift<8>(d);
        return din;
    }
    
    template <uint8_t W>
    static uint32_t _DRShift(uint32_t d) {
        _DRShiftStart();
        const uint32_t din = _Shift<W>(d);
        return din;
    }
    
    static uint8_t _JTAGIDGet() {
        const uint8_t din = _IRShift(_IR_CNTRL_SIG_CAPTURE);
        return din;
    }
    
    static bool _JTAGFuseBlown() {
        _IRShift(_IR_CNTRL_SIG_CAPTURE);
        const uint16_t din = _DRShift<16>(0xAAAA);
        return din == 0x5555;
    }
    
    static uint16_t _CoreID() {
        _IRShift(_IR_COREIP_ID);
        const uint16_t din = _DRShift<16>(0);
        return din;
    }
    
    static uint32_t _DeviceIDAddr() {
        _IRShift(_IR_DEVICE_ID);
        const uint32_t din = _DRShift<20>(0);
        return din;
    }
    
    static uint16_t _DeviceIDGet() {
        const uint32_t deviceIDAddr = _DeviceIDAddr()+4;
        const uint16_t deviceID = _Read16(deviceIDAddr);
        return deviceID;
    }
    
    static void _TclkSet(bool tclk) {
        _SBWIO(0, _TclkSaved, tclk);
        _TclkSaved = tclk;
    }
    
    static bool _FullEmulationState() {
        // Return whether the device is in full-emulation state
        _IRShift(_IR_CNTRL_SIG_CAPTURE);
        return _DRShift<16>(0) & 0x0301;
    }
    
    static bool _CPUReset() {
        // One clock to empty the pipe
        _TclkSet(0);
        _TclkSet(1);
        
        // Reset CPU
        _IRShift(_IR_CNTRL_SIG_16BIT);
        _DRShift<16>(0x0C01); // Deassert CPUSUSP, assert POR
        _DRShift<16>(0x0401); // Deassert POR
        
        // Set PC to 'safe' memory location
        _IRShift(_IR_DATA_16BIT);
        _TclkSet(0);
        _TclkSet(1);
        _TclkSet(0);
        _TclkSet(1);
        _DRShift<16>(_SafePC);
        // PC is set to 0x4 - MAB value can be 0x6 or 0x8
        
        // Drive safe address into PC
        _TclkSet(0);
        _TclkSet(1);
        _IRShift(_IR_DATA_CAPTURE);
        // Two more clocks to release CPU internal POR delay signals
        _TclkSet(0);
        _TclkSet(1);
        _TclkSet(0);
        _TclkSet(1);
        
        // Set CPUSUSP signal again
        _IRShift(_IR_CNTRL_SIG_16BIT);
        _DRShift<16>(0x0501);
        // One more clock
        _TclkSet(0);
        _TclkSet(1);
        // <- CPU in Full-Emulation-State
        
        // Disable Watchdog Timer on target device now by setting the HOLD signal
        // in the WDT_CNTRL register
        _Write16(0x01CC, 0x5A80);
        
        // Check if device is in Full-Emulation-State and return status
        if (!_FullEmulationState()) return false;
        return true;
    }
    
    static bool _CPUSyncWait() {
        for (int i=0; i<50; i++) {
            _IRShift(_IR_CNTRL_SIG_CAPTURE);
            if (_DRShift<16>(0) & 0x0200) return true;
        }
        return false;
    }
    
    static bool _MPUDisable() {
        constexpr uint16_t PasswordMask = 0xFF00;
        constexpr uint16_t Password = 0xA500;
        constexpr uint16_t MPUMask = 0x0003;
        constexpr uint16_t MPUDisabled = 0x0000;
        uint16_t reg = _Read16(_SYSCFG0Addr);
        reg &= ~(PasswordMask|MPUMask); // Clear password and MPU protection bits
        reg |= (Password|MPUDisabled); // Password
        _Write16(_SYSCFG0Addr, reg);
        // Verify that the MPU protection bits are cleared
        return (_Read16(_SYSCFG0Addr)&MPUMask) == MPUDisabled;
    }
    
    // CPU must be in Full-Emulation-State
    static void _PCSet(uint32_t addr) {
        constexpr uint16_t movInstr = 0x0080;
        const uint16_t pcHigh = ((addr>>8)&0xF00);
        const uint16_t pcLow = ((addr & 0xFFFF));
        
        _TclkSet(0);
        // Take over bus control during clock LOW phase
        _IRShift(_IR_DATA_16BIT);
        _TclkSet(1);
        _DRShift<16>(pcHigh | movInstr);
        _TclkSet(0);
        _IRShift(_IR_CNTRL_SIG_16BIT);
        _DRShift<16>(0x1400);
        _IRShift(_IR_DATA_16BIT);
        _TclkSet(0);
        _TclkSet(1);
        _DRShift<16>(pcLow);
        _TclkSet(0);
        _TclkSet(1);
        _DRShift<16>(0x4303);
        _TclkSet(0);
        _IRShift(_IR_ADDR_CAPTURE);
        _DRShift<20>(0);
    }
    
    template <typename T>
    static T _Read(uint32_t addr) {
        static_assert(std::is_same_v<T,uint8_t> || std::is_same_v<T,uint16_t>, "invalid type");
        AssertArg(!(addr % sizeof(T))); // Address must be naturally aligned
        
        // This is the 'quick' read implementation, because the non-quick
        // version doesn't appear to work with some addresses. (Specifically,
        // the device ID address, 0x1A04, always returns 0x3FFF.)
        // We'd prefer the non-quick version since it explicitly supports
        // byte reads in addition to word reads, while it's unclear whether
        // the quick version supports byte reads.
        // However byte reads appear to work fine with the quick version
        // (including at the end of the address space, and at the start/end
        // of regions).
        // In addition, unaligned word reads also appear to work, even
        // when straddling different regions (eg FRAM and ROM).
        _PCSet(addr);
        _TclkSet(1);
        _IRShift(_IR_CNTRL_SIG_16BIT);
        _DRShift<16>(std::is_same_v<T,uint8_t> ? 0x0511 : 0x0501);
        _IRShift(_IR_ADDR_CAPTURE);
        _IRShift(_IR_DATA_QUICK);
        _TclkSet(1);
        _TclkSet(0);
        
        if constexpr (std::is_same_v<T,uint8_t>) {
            if (addr & 1)   return _DRShift<8>(0);
            else            return _DRShift<16>(0) & 0x00FF;
        } else {
            return _DRShift<16>(0);
        }
    }
    
    static uint8_t _Read8(uint32_t addr) {
        return _Read<uint8_t>(addr);
    }
    
    static uint16_t _Read16(uint32_t addr) {
        return _Read<uint16_t>(addr);
    }
    
    // General-purpose read
    //   
    //   Works for: peripherals, RAM, FRAM
    //   
    //   This is the 'quick' read implementation suggested by JTAG guide
    static void _Read(uint32_t addr, uint8_t* dst, size_t len) {
        while (len) {
            // Read first/last byte
            if ((addr&1) || (len==1)) {
                *dst = _Read8(addr);
                addr++;
                dst++;
                len--;
            }
            
            // Read 16-bit words ('quick' implementation)
            if (len > 1) {
                _PCSet(addr);
                _TclkSet(1);
                _IRShift(_IR_CNTRL_SIG_16BIT);
                _DRShift<16>(0x0501);
                _IRShift(_IR_ADDR_CAPTURE);
                _IRShift(_IR_DATA_QUICK);
                
                while (len > 1) {
                    _TclkSet(1);
                    _TclkSet(0);
                    
                    const uint16_t w = _DRShift<16>(0);
                    memcpy(dst, &w, sizeof(w));
                    addr += 2;
                    dst += 2;
                    len -= 2;
                }
            }
        }
    }
    
    template <typename T>
    static void _Write(uint32_t addr, T val) {
        static_assert(std::is_same_v<T,uint8_t> || std::is_same_v<T,uint16_t>, "invalid type");
        AssertArg(!(addr % sizeof(T))); // Address must be naturally aligned
        
        // Activate write mode (clear read bit in JTAG control register)
        _TclkSet(0);
        _IRShift(_IR_CNTRL_SIG_16BIT);
        _DRShift<16>(std::is_same_v<T,uint8_t> ? 0x0510 : 0x0500);
        
        // Shift address to write to
        _IRShift(_IR_ADDR_16BIT);
        _DRShift<20>(addr);
        _TclkSet(1);
        
        // Shift data to write
        _IRShift(_IR_DATA_TO_ADDR);
        _DRShift<16>(val);
        _TclkSet(0);
        
        // Deactivate write mode (set read bit in JTAG control register)
        _IRShift(_IR_CNTRL_SIG_16BIT);
        _DRShift<16>(0x0501);
        _TclkSet(1);
        _TclkSet(0);
        _TclkSet(1);
    }
    
    static void _Write8(uint32_t addr, uint8_t val) {
        _Write<uint8_t>(addr, val);
    }
    
    static void _Write16(uint32_t addr, uint16_t val) {
        _Write<uint16_t>(addr, val);
    }
    
    // General-purpose write
    //   
    //   Works for: peripherals, RAM, FRAM
    //   
    //   This is the 'non-quick' write implementation suggested by JTAG guide
    static void _Write(uint32_t addr, const uint8_t* src, size_t len) {
        while (len) {
            // Write first/last byte
            if ((addr&1) || (len==1)) {
                _Write8(addr, *src);
                addr++;
                src++;
                len--;
            }
            
            // Write 16-bit words
            if (len > 1) {
                uint16_t w = 0;
                memcpy(&w, src, sizeof(w));
                
                _Write16(addr, w);
                
                addr += 2;
                src += 2;
                len -= 2;
            }
        }
    }
    
    // FRAM write
    //   Works for: FRAM
    //   
    //   This is a custom 'quick' implementation for writing.
    //   
    //   The JTAG guide claims this doesn't work ("For the MSP430Xv2
    //   architecture ... there is no specific implementation of a quick
    //   write operation") but it seems to work for FRAM, and is a lot
    //   faster than the suggested implementation.
    //   
    //   This technique has been confirmed to fail in these situations:
    //   - Writing to RAM (has no effect)
    //   - Writing to peripherals (clears the preceding word)
    static void _FRAMWrite(uint32_t addr, const uint8_t* src, size_t len) {
        while (len) {
            // Write first/last byte
            if ((addr&1) || (len==1)) {
                _Write8(addr, *src);
                addr++;
                src++;
                len--;
            }
            
            // Write 16-bit words ('quick' implementation)
            if (len > 1) {
                _PCSet(addr-2);
                _TclkSet(1);
                
                // Activate write mode (clear read bit in JTAG control register)
                _IRShift(_IR_CNTRL_SIG_16BIT);
                _DRShift<16>(0x0500);
                _IRShift(_IR_DATA_QUICK);
                _TclkSet(0);
                
                while (len > 1) {
                    uint16_t w = 0;
                    memcpy(&w, src, sizeof(w));
                    
                    _TclkSet(1);
                    _DRShift<16>(w);
                    _TclkSet(0);
                    
                    addr += 2;
                    src += 2;
                    len -= 2;
                }
                
                // Deactivate write mode (set read bit in JTAG control register)
                _IRShift(_IR_CNTRL_SIG_16BIT);
                _DRShift<16>(0x0501);
                _TclkSet(1);
                _TclkSet(0);
                _TclkSet(1);
            }
        }
    }
    
    static bool _JMBErase() {
        _IRShift(_IR_JMB_EXCHANGE);
        bool ready = false;
        for (int i=0; i<3000 && !ready; i++) {
            ready = _DRShift<16>(0) & _JMBMailboxIn0Ready;
        }
        if (!ready) return false; // Timeout
        
        _DRShift<16>(_JMBWidth32 | _JMBDirWrite);
        _DRShift<16>(_JMBMagicNum);
        _DRShift<16>(_JMBEraseCmd);
        return true;
    }
    
    static bool _JMBRead(uint32_t* val=nullptr) {
        _IRShift(_IR_JMB_EXCHANGE);
        if (!(_DRShift<16>(0) & _JMBMailboxOut1Ready)) return false;
        _DRShift<16>(_JMBWidth32 | _JMBDirRead);
        const uint32_t low = _DRShift<16>(0);
        const uint32_t high = _DRShift<16>(0);
        if (val) *val = (high<<16)|low;
        return true;
    }
    
    static void _JTAGStart(bool rst_) {
        // We have strict timing requirements, so disable interrupts.
        // Specifically, the low cycle of TCK can't be longer than 7us,
        // otherwise SBW will be disabled.
        Toastbox::IntState ints(false);
        
        // Reset pin states
        {
            _PinsReset();
        }
        
        // Reset the MSP430 so that it starts from a known state
        {
            _Rst_::Write(0);
            _DelayUs(0);
        }
        
        // Enable test mode
        {
            // Apply the supplied reset state, `rst_`
            _Rst_::Write(rst_);
            _DelayUs(0);
            // Assert TEST
            _Test::Write(1);
            _DelayUs(100);
        }
        
        // Choose 2-wire/Spy-bi-wire mode
        {
            // TDIO=1 while applying a single clock to TCK
            _Rst_::Write(1);
            _DelayUs(0);
            
            _Test::Write(0);
            _DelayUs(0);
            _Test::Write(1);
            _DelayUs(0);
        }
    }
    
    static void _JTAGEnd() {
        // Read the SYSRSTIV register to clear it, to emulate a real power-up
        _Read16(_SYSRSTIVAddr);
        
        // Perform a BOR (brownout reset)
        // TI's code claims that this resets the device and causes us to lose JTAG control,
        // but empirically we still need to execute the 'Reset CPU' and '_IR_CNTRL_SIG_RELEASE' stages below.
        // 
        // Note that a BOR still doesn't reset some modules (like RTC and PMM), but it's as close as
        // we can get to a full reset without power cycling the device.
        _IRShift(_IR_TEST_REG);
        _DRShift<16>(0x0200);
        
        // Reset CPU
        _IRShift(_IR_CNTRL_SIG_16BIT);
        _DRShift<16>(0x0C01); // Deassert CPUSUSP, assert POR
        _DRShift<16>(0x0401); // Deassert POR
        
        // Release JTAG control
        _IRShift(_IR_CNTRL_SIG_RELEASE);
        
        // Return pins to default state
        _PinsReset();
    }
};

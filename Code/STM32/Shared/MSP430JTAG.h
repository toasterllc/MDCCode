#pragma once
#include <string.h>
#include <type_traits>
#include "GPIO.h"
#include "Toastbox/IntState.h"

template <typename Test, typename Rst_, uint8_t CPUFreqMHz>
class MSP430JTAG {
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
    static constexpr uint16_t _DeviceID             = 0x8311;
    static constexpr uint32_t _SafePC               = 0x00000004;
    static constexpr uint32_t _SYSRSTIVAddr         = 0x0000015E;
    static constexpr uint32_t _SYSCFG0Addr          = 0x00000160;
    
    static constexpr uint16_t JMBMailboxIn0Ready    = 0x0001;
    static constexpr uint16_t JMBMailboxIn1Ready    = 0x0002;
    static constexpr uint16_t JMBMailboxOut0Ready   = 0x0004;
    static constexpr uint16_t JMBMailboxOut1Ready   = 0x0008;
    static constexpr uint16_t JMBDirWrite           = 0x0001; // Direction = writing into mailbox
    static constexpr uint16_t JMBDirRead            = 0x0004; // Direction = reading from mailbox
    static constexpr uint16_t JMBWidth32            = 0x0010; // 32-bit operation
    static constexpr uint16_t JMBMagicNum           = 0xA55A;
    static constexpr uint16_t JMBEraseCmd           = 0x1A1A;
    
    // _DelayUs: primitive delay implementation
    // Assumes a simple for loop takes 1 clock cycle per iteration
    static void _DelayUs(uint32_t us) {
        const uint32_t cycles = CPUFreqMHz*us;
        for (volatile uint32_t i=0; i<cycles; i++);
    }
    
    static constexpr bool _FRAMAddr(uint32_t addr) {
        return addr>=0xE300 && addr<=0xFFFF;
    }
    
    using _TCK = Test;
    using _TDIO = Rst_;
    
    bool _connected = false;
    bool _tclkSaved = 1;
    uint16_t _crc = 0;
    uint32_t _crcAddr = 0;
    size_t _crcLen = 0;
    bool _crcStarted = false;
    
    void _pinsReset() {
        // De-assert RST_ before de-asserting TEST, because the MSP430 latches RST_
        // as being asserted, if it's asserted when when TEST is de-asserted
        Rst_::Write(1);
        Rst_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _DelayUs(10);
        
        Test::Write(0);
        Test::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _DelayUs(200);
    }
    
    void _tapReset() {
        // Reset JTAG state machine
        // TMS=1 for 6 clocks
        for (int i=0; i<6; i++) {
            _sbwio(1, 1);
        }
        // <- Test-Logic-Reset
        
        // TMS=0 for 1 clock
        _sbwio(0, 1);
        // <- Run-Test/Idle
    }
    
    void _irShiftStart() {
        // <- Run-Test/Idle
        _sbwio(1, _tclkSaved);
        // <- Select DR-Scan
        _sbwio(1, 1);
        // <- Select IR-Scan
        _sbwio(0, 1);
        // <- Capture-IR
        _sbwio(0, 1);
        // <- Shift-IR
    }
    
    void _drShiftStart() {
        // <- Run-Test/Idle
        _sbwio(1, _tclkSaved);
        // <- Select DR-Scan
        _sbwio(0, 1);
        // <- Capture-IR
        _sbwio(0, 1);
        // <- Shift-DR
    }
    
    // Perform a single Spy-bi-wire I/O cycle
    __attribute__((noinline))
    bool _sbwio(bool tms, bool tclk, bool tdi) {
        // We have strict timing requirements, so disable interrupts.
        // Specifically, the low cycle of TCK can't be longer than 7us,
        // otherwise SBW will be disabled.
        Toastbox::IntState ints(false);
        
        // Write TMS
        {
            _TDIO::Write(tms);
            _DelayUs(0);
            
            _TCK::Write(0);
            _DelayUs(0);
            
            _TDIO::Write(tclk);
            _TCK::Write(1);
            _DelayUs(0);
        }
        
        // Write TDI
        {
            _TDIO::Write(tdi);
            _DelayUs(0);
            
            _TCK::Write(0);
            _DelayUs(0);
            
            _TCK::Write(1);
            // Stop driving SBWTDIO, in preparation for the slave to start driving it
            _TDIO::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
            _DelayUs(0);
        }
        
        // Read TDO
        bool tdo = 0;
        {
            _TCK::Write(0);
            _DelayUs(0);
            // Read the TDO value, driven by the slave, while SBWTCK=0
            tdo = _TDIO::Read();
            _TCK::Write(1);
            _DelayUs(0);
            
            // Start driving SBWTDIO again
            _TDIO::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        }
        
        return tdo;
    }
    
    bool _sbwio(bool tms, bool tdi) {
        // With no `tclk` specified, use the value for TMS, so that the line stays constant
        // between registering the TMS value and outputting the TDI value
        return _sbwio(tms, tms, tdi);
    }
    
    // Shifts `dout` MSB first
    template <uint8_t W>
    __attribute__((noinline))
    uint32_t _shift(uint32_t dout) {
        const uint32_t mask = (uint32_t)1<<(W-1);
        // <- Shift-DR / Shift-IR
        uint32_t din = 0;
        for (uint8_t i=0; i<W; i++) {
            const bool tms = (i<(W-1) ? 0 : 1); // Final bit needs TMS=1
            din <<= 1;
            din |= _sbwio(tms, dout&mask);
            dout <<= 1;
        }
        
        // <- Exit1-DR / Exit1-IR
        _sbwio(1, 1);
        // <- Update-DR / Update-IR
        _sbwio(0, _tclkSaved);
        // <- Run-Test/Idle
        
        return din;
    }
    
    uint8_t _irShift(uint8_t d) {
        _irShiftStart();
        const uint8_t din = _shift<8>(d);
        return din;
    }
    
    template <uint8_t W>
    uint32_t _drShift(uint32_t d) {
        _drShiftStart();
        const uint32_t din = _shift<W>(d);
        return din;
    }
    
    uint8_t _jtagID() {
        const uint8_t din = _irShift(_IR_CNTRL_SIG_CAPTURE);
        return din;
    }
    
    bool _jtagFuseBlown() {
        _irShift(_IR_CNTRL_SIG_CAPTURE);
        const uint16_t din = _drShift<16>(0xAAAA);
        return din == 0x5555;
    }
    
    uint16_t _coreID() {
        _irShift(_IR_COREIP_ID);
        const uint16_t din = _drShift<16>(0);
        return din;
    }
    
    uint32_t _deviceIDAddr() {
        _irShift(_IR_DEVICE_ID);
        const uint32_t din = _drShift<20>(0);
        return din;
    }
    
    uint16_t _deviceID() {
        const uint32_t deviceIDAddr = _deviceIDAddr()+4;
        const uint16_t deviceID = _read16(deviceIDAddr);
        return deviceID;
    }
    
    void _tclkSet(bool tclk) {
        _sbwio(0, _tclkSaved, tclk);
        _tclkSaved = tclk;
    }
    
    bool _fullEmulationState() {
        // Return whether the device is in full-emulation state
        _irShift(_IR_CNTRL_SIG_CAPTURE);
        return _drShift<16>(0) & 0x0301;
    }
    
    bool _cpuReset() {
        // One clock to empty the pipe
        _tclkSet(0);
        _tclkSet(1);
        
        // Reset CPU
        _irShift(_IR_CNTRL_SIG_16BIT);
        _drShift<16>(0x0C01); // Deassert CPUSUSP, assert POR
        _drShift<16>(0x0401); // Deassert POR
        
        // Set PC to 'safe' memory location
        _irShift(_IR_DATA_16BIT);
        _tclkSet(0);
        _tclkSet(1);
        _tclkSet(0);
        _tclkSet(1);
        _drShift<16>(_SafePC);
        // PC is set to 0x4 - MAB value can be 0x6 or 0x8
        
        // Drive safe address into PC
        _tclkSet(0);
        _tclkSet(1);
        _irShift(_IR_DATA_CAPTURE);
        // Two more clocks to release CPU internal POR delay signals
        _tclkSet(0);
        _tclkSet(1);
        _tclkSet(0);
        _tclkSet(1);
        
        // Set CPUSUSP signal again
        _irShift(_IR_CNTRL_SIG_16BIT);
        _drShift<16>(0x0501);
        // One more clock
        _tclkSet(0);
        _tclkSet(1);
        // <- CPU in Full-Emulation-State
        
        // Disable Watchdog Timer on target device now by setting the HOLD signal
        // in the WDT_CNTRL register
        _write16(0x01CC, 0x5A80);
        
        // Check if device is in Full-Emulation-State and return status
        if (!_fullEmulationState()) return false;
        return true;
    }
    
    bool _waitForCPUSync() {
        for (int i=0; i<50; i++) {
            _irShift(_IR_CNTRL_SIG_CAPTURE);
            if (_drShift<16>(0) & 0x0200) return true;
        }
        return false;
    }
    
    bool _mpuDisable() {
        constexpr uint16_t PasswordMask = 0xFF00;
        constexpr uint16_t Password = 0xA500;
        constexpr uint16_t MPUMask = 0x0003;
        constexpr uint16_t MPUDisabled = 0x0000;
        uint16_t reg = _read16(_SYSCFG0Addr);
        reg &= ~(PasswordMask|MPUMask); // Clear password and MPU protection bits
        reg |= (Password|MPUDisabled); // Password
        _write16(_SYSCFG0Addr, reg);
        // Verify that the MPU protection bits are cleared
        return (_read16(_SYSCFG0Addr)&MPUMask) == MPUDisabled;
    }
    
    // CPU must be in Full-Emulation-State
    void _pcSet(uint32_t addr) {
        constexpr uint16_t movInstr = 0x0080;
        const uint16_t pcHigh = ((addr>>8)&0xF00);
        const uint16_t pcLow = ((addr & 0xFFFF));
        
        _tclkSet(0);
        // Take over bus control during clock LOW phase
        _irShift(_IR_DATA_16BIT);
        _tclkSet(1);
        _drShift<16>(pcHigh | movInstr);
        _tclkSet(0);
        _irShift(_IR_CNTRL_SIG_16BIT);
        _drShift<16>(0x1400);
        _irShift(_IR_DATA_16BIT);
        _tclkSet(0);
        _tclkSet(1);
        _drShift<16>(pcLow);
        _tclkSet(0);
        _tclkSet(1);
        _drShift<16>(0x4303);
        _tclkSet(0);
        _irShift(_IR_ADDR_CAPTURE);
        _drShift<20>(0);
    }
    
    void _crcStart(uint32_t addr) {
        _crc = addr-2;
        _crcAddr = addr;
        _crcLen = 0;
        _crcStarted = true;
    }
    
    void _crcUpdate(uint16_t val) {
        constexpr uint16_t Poly = 0x0805;
        if (_crc & 0x8000) {
            _crc ^= Poly;
            _crc <<= 1;
            _crc |= 0x0001;
        } else {
            _crc <<= 1;
        }
        _crc ^= val;
    }
    
    uint16_t _crcCalc(uint32_t addr, size_t len) {
        AssertArg(!(addr & 1)); // Address must be 16-bit aligned
        AssertArg(!(len & 1)); // Length must be 16-bit aligned
        
        _pcSet(addr);
        _tclkSet(1);
        
        _irShift(_IR_CNTRL_SIG_16BIT);
        _drShift<16>(0x0501);
        
        _irShift(_IR_DATA_16BIT);
        _drShift<16>(addr-2);
        
        _irShift(_IR_DATA_PSA);
        
        for (size_t i=0; i<len; i+=2) {
            _tclkSet(0);
            _sbwio(1, 1);
            // <- Select DR-Scan
            _sbwio(0, 1);
            // <- Capture-DR
            _sbwio(0, 1);
            // <- Shift-DR
            _sbwio(1, 1);
            // <- Exit1-DR
            _sbwio(1, 1);
            // <- Update-DR
            _sbwio(0, 1);
            // <- Run-Test/Idle
            _tclkSet(1);
        }
        
        _irShift(_IR_SHIFT_OUT_PSA);
        return _drShift<16>(0);
    }
    
    template <typename T>
    T _read(uint32_t addr) {
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
        _pcSet(addr);
        _tclkSet(1);
        _irShift(_IR_CNTRL_SIG_16BIT);
        _drShift<16>(std::is_same_v<T,uint8_t> ? 0x0511 : 0x0501);
        _irShift(_IR_ADDR_CAPTURE);
        _irShift(_IR_DATA_QUICK);
        _tclkSet(1);
        _tclkSet(0);
        
        if constexpr (std::is_same_v<T,uint8_t>) {
            if (addr & 1)   return _drShift<8>(0);
            else            return _drShift<16>(0) & 0x00FF;
        } else {
            return _drShift<16>(0);
        }
    }
    
    uint8_t _read8(uint32_t addr) {
        return _read<uint8_t>(addr);
    }
    
    uint16_t _read16(uint32_t addr) {
        return _read<uint16_t>(addr);
    }
    
    // General-purpose read
    //   
    //   Works for: peripherals, RAM, FRAM
    //   
    //   This is the 'quick' read implementation suggested by JTAG guide
    void _read(uint32_t addr, uint8_t* dst, size_t len) {
        while (len) {
            // Read first/last byte
            if ((addr&1) || (len==1)) {
                *dst = _read8(addr);
                addr++;
                dst++;
                len--;
            }
            
            // Read 16-bit words ('quick' implementation)
            if (len > 1) {
                _pcSet(addr);
                _tclkSet(1);
                _irShift(_IR_CNTRL_SIG_16BIT);
                _drShift<16>(0x0501);
                _irShift(_IR_ADDR_CAPTURE);
                _irShift(_IR_DATA_QUICK);
                
                while (len > 1) {
                    _tclkSet(1);
                    _tclkSet(0);
                    
                    const uint16_t w = _drShift<16>(0);
                    memcpy(dst, &w, sizeof(w));
                    addr += 2;
                    dst += 2;
                    len -= 2;
                }
            }
        }
    }
    
    template <typename T>
    void _write(uint32_t addr, T val) {
        static_assert(std::is_same_v<T,uint8_t> || std::is_same_v<T,uint16_t>, "invalid type");
        AssertArg(!(addr % sizeof(T))); // Address must be naturally aligned
        
        // Activate write mode (clear read bit in JTAG control register)
        _tclkSet(0);
        _irShift(_IR_CNTRL_SIG_16BIT);
        _drShift<16>(std::is_same_v<T,uint8_t> ? 0x0510 : 0x0500);
        
        // Shift address to write to
        _irShift(_IR_ADDR_16BIT);
        _drShift<20>(addr);
        _tclkSet(1);
        
        // Shift data to write
        _irShift(_IR_DATA_TO_ADDR);
        _drShift<16>(val);
        _tclkSet(0);
        
        // Deactivate write mode (set read bit in JTAG control register)
        _irShift(_IR_CNTRL_SIG_16BIT);
        _drShift<16>(0x0501);
        _tclkSet(1);
        _tclkSet(0);
        _tclkSet(1);
    }
    
    void _write8(uint32_t addr, uint8_t val) {
        _write<uint8_t>(addr, val);
    }
    
    void _write16(uint32_t addr, uint16_t val) {
        _write<uint16_t>(addr, val);
    }
    
    // General-purpose write
    //   
    //   Works for: peripherals, RAM, FRAM
    //   
    //   This is the 'non-quick' write implementation suggested by JTAG guide
    void _write(uint32_t addr, const uint8_t* src, size_t len) {
        while (len) {
            // Write first/last byte
            if ((addr&1) || (len==1)) {
                _write8(addr, *src);
                addr++;
                src++;
                len--;
            }
            
            // Write 16-bit words
            if (len > 1) {
                uint16_t w = 0;
                memcpy(&w, src, sizeof(w));
                
                _write16(addr, w);
                
                _crcUpdate(w);
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
    void _framWrite(uint32_t addr, const uint8_t* src, size_t len) {
        while (len) {
            // Write first/last byte
            if ((addr&1) || (len==1)) {
                _write8(addr, *src);
                addr++;
                src++;
                len--;
            }
            
            // Write 16-bit words ('quick' implementation)
            if (len > 1) {
                _pcSet(addr-2);
                _tclkSet(1);
                
                // Activate write mode (clear read bit in JTAG control register)
                _irShift(_IR_CNTRL_SIG_16BIT);
                _drShift<16>(0x0500);
                _irShift(_IR_DATA_QUICK);
                _tclkSet(0);
                
                while (len > 1) {
                    uint16_t w = 0;
                    memcpy(&w, src, sizeof(w));
                    
                    _tclkSet(1);
                    _drShift<16>(w);
                    _tclkSet(0);
                    
                    _crcUpdate(w);
                    addr += 2;
                    src += 2;
                    len -= 2;
                }
                
                // Deactivate write mode (set read bit in JTAG control register)
                _irShift(_IR_CNTRL_SIG_16BIT);
                _drShift<16>(0x0501);
                _tclkSet(1);
                _tclkSet(0);
                _tclkSet(1);
            }
        }
    }
    
    bool _jmbErase() {
        _irShift(_IR_JMB_EXCHANGE);
        bool ready = false;
        for (int i=0; i<3000 && !ready; i++) {
            ready = _drShift<16>(0) & JMBMailboxIn0Ready;
        }
        if (!ready) return false; // Timeout
        
        _drShift<16>(JMBWidth32 | JMBDirWrite);
        _drShift<16>(JMBMagicNum);
        _drShift<16>(JMBEraseCmd);
        return true;
    }
    
    bool _jmbRead(uint32_t* val=nullptr) {
        _irShift(_IR_JMB_EXCHANGE);
        if (!(_drShift<16>(0) & JMBMailboxOut1Ready)) return false;
        _drShift<16>(JMBWidth32 | JMBDirRead);
        const uint32_t low = _drShift<16>(0);
        const uint32_t high = _drShift<16>(0);
        if (val) *val = (high<<16)|low;
        return true;
    }
    
    void _jtagStart(bool rst_) {
        // We have strict timing requirements, so disable interrupts.
        // Specifically, the low cycle of TCK can't be longer than 7us,
        // otherwise SBW will be disabled.
        Toastbox::IntState ints(false);
        
        // Reset pin states
        {
            _pinsReset();
        }
        
        // Reset the MSP430 so that it starts from a known state
        {
            Rst_::Write(0);
            _DelayUs(0);
        }
        
        // Enable test mode
        {
            // Apply the supplied reset state, `rst_`
            Rst_::Write(rst_);
            _DelayUs(0);
            // Assert TEST
            Test::Write(1);
            _DelayUs(100);
        }
        
        // Choose 2-wire/Spy-bi-wire mode
        {
            // TDIO=1 while applying a single clock to TCK
            _TDIO::Write(1);
            _DelayUs(0);
            
            _TCK::Write(0);
            _DelayUs(0);
            _TCK::Write(1);
            _DelayUs(0);
        }
    }
    
    void _jtagEnd() {
        // Read the SYSRSTIV register to clear it, to emulate a real power-up
        _read16(_SYSRSTIVAddr);
        
        // Perform a BOR (brownout reset)
        // TI's code claims that this resets the device and causes us to lose JTAG control,
        // but empirically we still need to execute the 'Reset CPU' and '_IR_CNTRL_SIG_RELEASE' stages below.
        // 
        // Note that a BOR still doesn't reset some modules (like RTC and PMM), but it's as close as
        // we can get to a full reset without power cycling the device.
        _irShift(_IR_TEST_REG);
        _drShift<16>(0x0200);
        
        // Reset CPU
        _irShift(_IR_CNTRL_SIG_16BIT);
        _drShift<16>(0x0C01); // Deassert CPUSUSP, assert POR
        _drShift<16>(0x0401); // Deassert POR
        
        // Release JTAG control
        _irShift(_IR_CNTRL_SIG_RELEASE);
        
        // Return pins to default state
        _pinsReset();
    }
    
public:
    enum class Status {
        OK,
        Error,
        JTAGDisabled,
    };
    
    void init() {
        _pinsReset();
    }
    
    Status connect() {
        if (_connected) return Status::OK; // Short-circuit
        
        for (int i=0; i<3; i++) {
            // Perform JTAG entry sequence with RST_=1
            _jtagStart(1);
            
            // Reset JTAG state machine (test access port, TAP)
            _tapReset();
            
            // Validate the JTAG ID
            if (_jtagID() != _JTAGID) {
                continue; // Try again
            }
            
            // Check JTAG fuse blown state
            if (_jtagFuseBlown()) {
                return Status::JTAGDisabled;
            }
            
            // Validate the Core ID
            if (_coreID() == 0) {
                continue; // Try again
            }
            
            // Set device into JTAG mode + read
            _irShift(_IR_CNTRL_SIG_16BIT);
            _drShift<16>(0x1501);
            
            // Wait until CPU is sync'd
            if (!_waitForCPUSync()) {
                continue;
            }
            
            // Reset CPU
            if (!_cpuReset()) {
                continue; // Try again
            }
            
            // Validate the Device ID
            {
                const uint16_t deviceID = _deviceID();
                if (deviceID != _DeviceID) {
                    continue; // Try again
                }
            }
            
            // Disable MPU (so we can write to FRAM)
            if (!_mpuDisable()) {
                continue; // Try again
            }
            
            // Nothing failed!
            _connected = true;
            return Status::OK;
        }
        
        // Too many failures
        return Status::Error;
    }
    
    void disconnect() {
        if (!_connected) return; // Short-circuit
        _jtagEnd();
        _connected = false;
    }
    
    Status erase() {
        // Perform JTAG entry sequence with RST_=0
        _jtagStart(0);
        // Reset JTAG TAP
        _tapReset();
        
        bool r = _jmbErase();
        if (!r) return Status::Error;
        
        _jtagEnd();
        return Status::OK;
    }
    
    uint16_t read(uint32_t addr) {
        return _read16(addr);
    }
    
    void read(uint32_t addr, void* dst, size_t len) {
        _read(addr, (uint8_t*)dst, len);
    }
    
    void write(uint32_t addr, uint16_t val) {
        _write16(addr, val);
    }
    
    void write(uint32_t addr, const void* src, size_t len) {
        if (!_crcStarted) _crcStart(addr);
        if (_FRAMAddr(addr) && _FRAMAddr(addr+len-1)) {
            // framWrite() is a write implementation that's faster than the
            // general-purpose write(), but only works for FRAM memory regions
            _framWrite(addr, (uint8_t*)src, len);
        } else {
            _write(addr, (uint8_t*)src, len);
        }
        _crcLen += len;
    }
    
    void crcReset() {
        _crcStarted = false;
    }
    
    Status crcVerify() {
        Assert(_crcStarted);
        return (_crcCalc(_crcAddr, _crcLen)==_crc ? Status::OK : Status::Error);
    }
    
    void debugTestSet(bool val) {
        // Write before configuring. If we configured before writing, we could drive the
        // wrong value momentarily before writing the correct value.
        Test::Write(val);
        Test::Config(GPIO_MODE_OUTPUT_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    }
    
    void debugRstSet(bool val) {
        // Write before configuring. If we configured before writing, we could drive the
        // wrong value momentarily before writing the correct value.
        Rst_::Write(val);
        Rst_::Config(GPIO_MODE_OUTPUT_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    }
    
    void debugTestPulse() {
        Toastbox::IntState ints(false);
        // Write before configuring. If we configured before writing, we could drive the
        // wrong value momentarily before writing the correct value.
        Test::Write(0);
        Test::Config(GPIO_MODE_OUTPUT_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        Test::Write(1);
    }
    
    bool debugSBWIO(bool tms, bool tclk, bool tdi) {
        return _sbwio(tms, tclk, tdi);
    }
};

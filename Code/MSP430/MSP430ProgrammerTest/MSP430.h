#pragma once
#include <msp430g2553.h>
#include "GPIO.h"
extern "C" {
#include "mspprintf.h"
}

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
    
    static constexpr uint8_t _Reverse(uint8_t x) {
        return (x&(1<<7))>>7 | (x&(1<<6))>>5 | (x&(1<<5))>>3 | (x&(1<<4))>>1 |
               (x&(1<<3))<<1 | (x&(1<<2))<<3 | (x&(1<<1))<<5 | (x&(1<<0))<<7 ;
    }
    
    static constexpr uint8_t _IR_CNTRL_SIG_16BIT    = _Reverse(0x13);
    static constexpr uint8_t _IR_CNTRL_SIG_CAPTURE  = _Reverse(0x14);
    static constexpr uint8_t _IR_CNTRL_SIG_RELEASE  = _Reverse(0x15);
    static constexpr uint8_t _IR_COREIP_ID          = _Reverse(0x17);
    
    static constexpr uint8_t _IR_DATA_16BIT         = _Reverse(0x41);
    static constexpr uint8_t _IR_DATA_CAPTURE       = _Reverse(0x42);
    static constexpr uint8_t _IR_DATA_QUICK         = _Reverse(0x43);
    
    static constexpr uint8_t _IR_DATA_PSA           = _Reverse(0x44);
    static constexpr uint8_t _IR_SHIFT_OUT_PSA      = _Reverse(0x46);
    
    static constexpr uint8_t _IR_JMB_EXCHANGE       = _Reverse(0x61);
    
    static constexpr uint8_t _IR_ADDR_16BIT         = _Reverse(0x83);
    static constexpr uint8_t _IR_ADDR_CAPTURE       = _Reverse(0x84);
    static constexpr uint8_t _IR_DATA_TO_ADDR       = _Reverse(0x85);
    static constexpr uint8_t _IR_DEVICE_ID          = _Reverse(0x87);
    
    static constexpr uint8_t _IR_BYPASS             = _Reverse(0xFF);
    
    static constexpr uint8_t _JTAGID                = 0x98;
    static constexpr uint16_t _DeviceID             = 0x8311;
    static constexpr uint32_t _SafePC               = 0x00000004;
    static constexpr uint32_t _SYSCFG0Addr          = 0x00000160;
    
    #define CPUFreqMHz 16
    #define _delayUs(us) __delay_cycles(CPUFreqMHz*us);
    
    static void _delayMs(uint32_t ms) {
        for (volatile uint32_t i=0; i<ms; i++) {
            _delayUs(1000);
        }
    }
    
    GPIOT& _test;
    GPIOR& _rst_;
    #define _tck _test
    #define _tdio _rst_
    
    TCLK _tclkSaved = TCLK1;
    uint16_t _crc = 0;
    bool _crcValid = false;
    
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
    __attribute__((noinline))
    uint8_t _sbwio(TMS tms, TDI tdi, bool restoreSavedTCLK=false) {
        // ## Write TMS
        {
            _tdio.write(tms);
            _delayUs(0);
            
            _tck.write(0);
            _delayUs(0);
            
            if (restoreSavedTCLK) {
                // Restore saved value of TCLK during TCK=0 period.
                // "To provide only a falling edge for ClrTCLK, the SBWTDIO signal
                // must be set high before entering the TDI slot."
                _tdio.write(_tclkSaved);
            }
            
            _tck.write(1);
            _delayUs(0);
        }
        
        // ## Write TDI
        {
            _tdio.write(tdi);
            _delayUs(0);
            
            _tck.write(0);
            _delayUs(0);
            
            _tck.write(1);
            // Stop driving SBWTDIO, in preparation for the slave to start driving it
            _tdio.config(0);
            _delayUs(0);
        }
        
        // ## Read TDO
        uint8_t tdo = TDO0;
        {
            _tck.write(0);
            _delayUs(0);
            // Read the TDO value, driven by the slave, while SBWTCK=0
            tdo = _tdio.read();
            _tck.write(1);
            _delayUs(0);
            
            // Start driving SBWTDIO again
            _tdio.config(1);
        }
        
        return tdo;
    }
    
    // Shifts `dout` MSB first
    template <uint8_t W>
    __attribute__((noinline))
    uint32_t _shift(uint32_t dout) {
        const uint32_t mask = (uint32_t)1<<(W-1);
        // <-- Shift-DR / Shift-IR
        uint32_t din = 0;
        for (uint8_t i=0; i<W; i++) {
            const TMS tms = (i<(W-1) ? TMS0 : TMS1); // Final bit needs TMS=1
            din <<= 1;
            din |= _sbwio(tms, dout&mask);
            dout <<= 1;
        }
        
        // <-- Exit1-DR / Exit1-IR
        _sbwio(TMS1, TDO1);
        // <-- Update-DR / Update-IR
        _sbwio(TMS0, _tclkSaved);
        // <-- Run-Test/Idle
        
        return din;
    }
    
    uint8_t _shiftIR(uint8_t d) {
        _startShiftIR();
        return _shift<8>(d);
    }
    
    template <uint8_t W>
    uint32_t _shiftDR(uint32_t d) {
        _startShiftDR();
        uint32_t din = _shift<W>(d);
        return din;
    }
    
    uint8_t _readJTAGID() {
        return _shiftIR(_IR_CNTRL_SIG_CAPTURE);
    }
    
    bool _readJTAGFuseBlown() {
        _shiftIR(_IR_CNTRL_SIG_CAPTURE);
        return _shiftDR<16>(0xAAAA) == 0x5555;
    }
    
    uint32_t _readCoreID() {
        _shiftIR(_IR_COREIP_ID);
        return _shiftDR<16>(0);
    }
    
    uint32_t _readDeviceIDAddr() {
        _shiftIR(_IR_DEVICE_ID);
        return _shiftDR<20>(0);
    }
    
    void _tclkSet(TCLK tclk) {
        _sbwio(TMS0, tclk, true);
        _tclkSaved = tclk;
    }
    
    bool _resetCPU() {
        // One clock to empty the pipe
        _tclkSet(0);
        _tclkSet(1);
        
        // Prepare access to the JTAG CNTRL SIG register
        _shiftIR(_IR_CNTRL_SIG_16BIT);
        // Release CPUSUSP signal and apply POR signal
        _shiftDR<16>(0x0C01);
        // Release POR signal again
        _shiftDR<16>(0x0401);
        
        // Set PC to 'safe' memory location
        _shiftIR(_IR_DATA_16BIT);
        _tclkSet(0);
        _tclkSet(1);
        _tclkSet(0);
        _tclkSet(1);
        _shiftDR<16>(_SafePC);
        // PC is set to 0x4 - MAB value can be 0x6 or 0x8
        
        // Drive safe address into PC
        _tclkSet(0);
        _tclkSet(1);
        _shiftIR(_IR_DATA_CAPTURE);
        // Two more clocks to release CPU internal POR delay signals
        _tclkSet(0);
        _tclkSet(1);
        _tclkSet(0);
        _tclkSet(1);
        
        // Set CPUSUSP signal again
        _shiftIR(_IR_CNTRL_SIG_16BIT);
        _shiftDR<16>(0x0501);
        // One more clock
        _tclkSet(0);
        _tclkSet(1);
        // <- CPU in Full-Emulation-State
        
        // Disable Watchdog Timer on target device now by setting the HOLD signal
        // in the WDT_CNTRL register
        uint16_t wdt = 0;
        _readMem(0x01CC, &wdt, 1);
        mspprintf("AAA wdt = %x\r\n", wdt);
        _writeMem(0x01CC, 0x5A80);
        _readMem(0x01CC, &wdt, 1);
        mspprintf("BBB wdt = %x\r\n", wdt);
//        for (;;);
        
        // Check if device is in Full-Emulation-State and return status
        _shiftIR(_IR_CNTRL_SIG_CAPTURE);
        if (!(_shiftDR<16>(0) & 0x0301)) {
            return false;
        }
        
        return true;
    }
    
    bool _waitForCPUSync() {
        for (int i=0; i<50; i++) {
            _shiftIR(_IR_CNTRL_SIG_CAPTURE);
            if (_shiftDR<16>(0) & 0x0200) return true;
        }
        return false;
    }
    
    bool _disableMPU() {
        constexpr uint16_t PasswordMask = 0xFF00;
        constexpr uint16_t Password = 0xA500;
        constexpr uint16_t MPUMask = 0x0003;
        constexpr uint16_t MPUDisabled = 0x0000;
        uint16_t val = 0;
        _readMem(_SYSCFG0Addr, &val, 1);
        val &= ~(PasswordMask|MPUMask); // Clear password and MPU protection bits
        val |= (Password|MPUDisabled); // Password
        _writeMem(_SYSCFG0Addr, &val, 1);
        // Verify that the MPU protection bits are cleared
        _readMem(_SYSCFG0Addr, &val, 1);
        return (val&MPUMask) == MPUDisabled;
    }
    
    // CPU must be in Full-Emulation-State
    void _setPC(uint32_t addr) {
        constexpr uint16_t movInstr = 0x0080;
        const uint16_t pcHigh = ((addr>>8)&0xF00);
        const uint16_t pcLow = ((addr & 0xFFFF));
        
        _tclkSet(0);
        // Take over bus control during clock LOW phase
        _shiftIR(_IR_DATA_16BIT);
        _tclkSet(1);
        _shiftDR<16>(pcHigh | movInstr);
        _tclkSet(0);
        _shiftIR(_IR_CNTRL_SIG_16BIT);
        _shiftDR<16>(0x1400);
        _shiftIR(_IR_DATA_16BIT);
        _tclkSet(0);
        _tclkSet(1);
        _shiftDR<16>(pcLow);
        _tclkSet(0);
        _tclkSet(1);
        _shiftDR<16>(0x4303);
        _tclkSet(0);
        _shiftIR(_IR_ADDR_CAPTURE);
        _shiftDR<20>(0);
    }
    
    void _readMem(uint32_t addr, uint16_t* dst, uint32_t len) {
        _setPC(addr);
        _tclkSet(1);
        _shiftIR(_IR_CNTRL_SIG_16BIT);
        _shiftDR<16>(0x0501);
        _shiftIR(_IR_ADDR_CAPTURE);
        _shiftIR(_IR_DATA_QUICK);
        
        for (; len; len--) {
            _tclkSet(1);
            _tclkSet(0);
            *dst = _shiftDR<16>(0);
            dst++;
        }
    }
    
    
//void WriteMemQuick_430X(unsigned long StartAddr, unsigned long Length, word *DataArray)
//{
//    unsigned long i;
//
//    // Initialize writing:
//    SetPC_430X(StartAddr-4);
//    HaltCPU();
//
//    ClrTCLK();
//    IR_Shift(IR_CNTRL_SIG_16BIT);
//    DR_Shift16(0x2408);             // Set RW to write
//    IR_Shift(IR_DATA_QUICK);
//    for (i = 0; i < Length; i++)
//    {
//        DR_Shift16(DataArray[i]);   // Shift in the write data
//        SetTCLK();
//        ClrTCLK();                  // Increment PC by 2
//    }
//    ReleaseCPU();
//}
    
    
    
//    void _writeMemQuick(uint32_t addr, const uint16_t* src, uint32_t len) {
//        // Word 0 works
//        _setPC(addr);
//        _tclkSet(0);
//        _shiftIR(_IR_CNTRL_SIG_16BIT);
//        _shiftDR<16>(0x0500);
//        _shiftIR(_IR_DATA_QUICK);
//        _tclkSet(1);
//        
//        _shiftDR<16>(*src);
//        src++;
//        _tclkSet(0);
//        _tclkSet(1);
//        
//        // Words 1,2,3 works
//        _setPC(addr);
//        _tclkSet(1);
//        _shiftIR(_IR_CNTRL_SIG_16BIT);
//        _shiftDR<16>(0x0500);
//        _shiftIR(_IR_DATA_QUICK);
//        
//        for (; len; len--) {
//            _shiftDR<16>(*src);
//            src++;
//            _tclkSet(0);
//            _tclkSet(1);
//        }
//    }
    
    
    
    void _writeMem(uint32_t addr, const uint16_t* src, uint32_t len) {
        constexpr uint16_t Poly = 0x0805;
        _setPC(addr-2);
        _tclkSet(1);
        _shiftIR(_IR_CNTRL_SIG_16BIT);
        _shiftDR<16>(0x0500);
        _shiftIR(_IR_DATA_QUICK);
        _tclkSet(0);
        _tclkSet(1);
        
        for (; len; len--) {
//            // Update CRC
//            {
//                if (_crc & 0x8000) {
//                    _crc ^= Poly;
//                    _crc <<= 1;
//                    _crc |= 0x0001;
//                } else {
//                    _crc <<= 1;
//                }
//                
//                _crc ^= *src;
//            }
            
            _tclkSet(1);
            _shiftDR<16>(*src);
            src++;
            _tclkSet(0);
        }
        
//        // Words 1,2,3 works
//        _setPC(addr);
//        _tclkSet(1);
//        _shiftIR(_IR_CNTRL_SIG_16BIT);
//        _shiftDR<16>(0x0500);
//        _shiftIR(_IR_DATA_QUICK);
//        
//        for (; len; len--) {
//            _shiftDR<16>(*src);
//            src++;
//            _tclkSet(0);
//            _tclkSet(1);
//        }
    }
    
    
    
    // Works when writing to WDT register
//    void _writeMem(uint32_t addr, const uint16_t* src, uint32_t len) {
//        // Word 0 works
//        _setPC(addr);
//        _tclkSet(0);
//        _shiftIR(_IR_CNTRL_SIG_16BIT);
//        _shiftDR<16>(0x0500);
//        _shiftIR(_IR_DATA_QUICK);
//        _tclkSet(1);
//        
//        _shiftDR<16>(*src);
//        src++;
//        _tclkSet(0);
//        _tclkSet(1);
//    }
    
    
    // Works when writing to FRAM, but seems to fail when writing to WDT register
//    void _writeMem(uint32_t addr, const uint16_t* src, uint32_t len) {
//        _setPC(addr-2);
//        _tclkSet(1);
//        _shiftIR(_IR_CNTRL_SIG_16BIT);
//        _shiftDR<16>(0x0500);
//        _shiftIR(_IR_DATA_QUICK);
//        _shiftDR<16>(0);
//        _tclkSet(0);
//        _tclkSet(1);
//        
//        for (; len; len--) {
//            _shiftDR<16>(*src);
//            src++;
//            _tclkSet(0);
//            _tclkSet(1);
//        }
//    }
    
//    void _writeMem(uint32_t addr, const uint16_t* src, uint32_t len) {
//        constexpr uint16_t Poly = 0x0805;
//        while (len) {
//            // Update CRC
//            {
//                if (_crc & 0x8000) {
//                    _crc ^= Poly;
//                    _crc <<= 1;
//                    _crc |= 0x0001;
//                } else {
//                    _crc <<= 1;
//                }
//                
//                _crc ^= *src;
//            }
//            
//            _tclkSet(0);
//            _shiftIR(_IR_CNTRL_SIG_16BIT);
//            _shiftDR<16>(0x0500);
//            
//            _shiftIR(_IR_ADDR_16BIT);
//            _shiftDR<20>(addr);
//            _tclkSet(1);
//            
//            // Only apply data during clock high phase
//            _shiftIR(_IR_DATA_TO_ADDR);
//            _shiftDR<16>(*src);
//            _tclkSet(0);
//            _shiftIR(_IR_CNTRL_SIG_16BIT);
//            _shiftDR<16>(0x0501);
//            _tclkSet(1);
//            // One or more cycle, so CPU is driving correct MAB
//            _tclkSet(0);
//            _tclkSet(1);
//            
//            addr += 2;
//            src++;
//            len--;
//        }
//    }
    
    void _writeMem(uint32_t addr, uint16_t val) {
        _writeMem(addr, &val, 1);
    }
    
//    void _writeMemQuick(uint32_t addr, uint16_t val) {
//        _writeMemQuick(addr, &val, 1);
//    }
    
    uint16_t _calcCRC(uint32_t addr, uint32_t len) {
        _setPC(addr);
        _tclkSet(1);
        
        _shiftIR(_IR_CNTRL_SIG_16BIT);
        _shiftDR<16>(0x0501);
        
        _shiftIR(_IR_DATA_16BIT);
        _shiftDR<16>(addr-2);
        
        _shiftIR(_IR_DATA_PSA);
        
        for (uint32_t i=0; i<len; i++) {
            _tclkSet(0);
            _sbwio(TMS1, TDI1);
            // <- Select DR-Scan
            _sbwio(TMS0, TDI1);
            // <- Capture-DR
            _sbwio(TMS0, TDI1);
            // <- Shift-DR
            _sbwio(TMS1, TDI1);
            // <- Exit1-DR
            _sbwio(TMS1, TDI1);
            // <- Update-DR
            _sbwio(TMS0, TDI1);
            // <- Run-Test/Idle
            _tclkSet(1);
        }
        
        _shiftIR(_IR_SHIFT_OUT_PSA);
        return _shiftDR<16>(0);
    }
    
//    void _erase() {
//        _shiftIR(_IR_JMB_EXCHANGE);
//        _shiftDR<16>(0xA55A); // Magic pattern
//        _shiftDR<16>(0x1A1A); // Erase
////        _delayMs(100); // Wait for erase to complete
//    }
    
    
    void EntrySequences_RstLow_SBW()
    {
        _test.write(0);                //1
        _delayMs(1);       // reset TEST logic
        
        _rst_.write(0);                //2
        _delayMs(50);
          
        _test.write(1);                //3
        _delayMs(100);     // activate TEST logic

        // phase 1
        _rst_.write(1);                //4
        _delayUs(40);

        // phase 2 -> TEST pin to 0, no change on RST pin
        // for Spy-Bi-Wire
        _test.write(0);                  //5
           
        _delayUs(1);

        // phase 4 -> TEST pin to 1, no change on RST pin
        // for Spy-Bi-Wire
        _test.write(1);      //7
        _delayUs(40);
        _delayMs(5);
    }
    
    void EntrySequences_RstHigh_SBW()
    {
        _test.write(0);    //1
        _delayMs(4); // reset TEST logic

        _rst_.write(1);    //2
        
        _test.write(1);    //3
        _delayMs(20); // activate TEST logic

        // phase 1
        _rst_.write(1);    //4
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
    
    void i_WriteJmbIn32(unsigned short dataX,unsigned short dataY) {
        // Constants for JTAG mailbox data exchange
        //! \brief JTAG mailbox constant - 
        #define OUT1RDY 0x0008
        //! \brief JTAG mailbox constant - 
        #define IN0RDY  0x0001
        //! \brief JTAG mailbox constant - 
        #define JMB32B  0x0010
        //! \brief JTAG mailbox constant - 
        #define OUTREQ  0x0004
        //! \brief JTAG mailbox constant - 
        #define INREQ   0x0001
        //! \brief JTAG mailbox mode 32 bit - 
        #define MAIL_BOX_32BIT 0x10
        //! \brief JTAG mailbox moede 16 bit - 
        #define MAIL_BOX_16BIT 0x00
        
        unsigned short sJMBINCTL;
        unsigned short sJMBIN0,sJMBIN1;
        unsigned long Timeout = 0;

        sJMBIN0 = (unsigned short)(dataX & 0x0000FFFF);
        sJMBIN1 = (unsigned short)(dataY & 0x0000FFFF);
        sJMBINCTL =  JMB32B | INREQ;

        _shiftIR(_IR_JMB_EXCHANGE); 
        do {
            Timeout++;
            if(Timeout >= 3000)
            {
                mspprintf("i_WriteJmbIn32 timeout\r\n");
                for (;;);
            }
        }
        while(!(_shiftDR<16>(0x0000) & IN0RDY) && Timeout < 3000);

        if (Timeout < 3000) {
            sJMBINCTL = 0x11;
            _shiftDR<16>(sJMBINCTL) ;
            _shiftDR<16>(sJMBIN0);
            _shiftDR<16>(sJMBIN1);
        }
    }
    
    void SyncJtag_AssertPor() {
        _shiftIR(_IR_CNTRL_SIG_16BIT);
        _shiftDR<16>(0x1501);                  // Set device into JTAG mode + read
        
        _shiftIR(_IR_CNTRL_SIG_CAPTURE);
        // wait for sync
        int i = 0;
        while(!(_shiftDR<16>(0) & 0x0200) && i < 50)
        {
            i++;
        };
        // continues if sync was successful
        if (i >= 50) {
            mspprintf("SyncJtag_AssertPor: too many retries\r\n");
            for (;;);
        }
        
        _resetCPU();
    }
    
    void _erase() {
        _test.write(0);
        _rst_.write(0);
        _delayMs(200);
        
        EntrySequences_RstLow_SBW();
        
        _tapReset();
        
        i_WriteJmbIn32(0xA55A, 0x1A1A);
        // restart device
        _test.write(0);
        _rst_.write(1);
        _delayMs(200);
        
        EntrySequences_RstHigh_SBW();
        _tapReset();
        _delayMs(60);
        
        SyncJtag_AssertPor();
    }
    
    
public:
    MSP430(GPIOT& test, GPIOR& rst_) :
    _test(test), _rst_(rst_)
    {}
    
    bool connect(bool allowErase=false) {
        for (int i=0; i<3; i++) {
            // ## Reset pin states
            {
                _test.write(0);
                _rst_.write(1);
                _delayMs(10);
            }
            
            // ## Reset the MSP430 so that it starts from a known state
            {
                _rst_.write(0);
                _delayUs(0);
            }
            
            // ## Enable test mode
            {
                // RST=1
                _rst_.write(1);
                _delayUs(0);
                // Assert TEST
                _test.write(1);
                _delayMs(1);
            }
            
            // ## Choose 2-wire/Spy-bi-wire mode
            {
                // TDIO=1 while applying a single clock to TCK
                _tdio.write(1);
                _delayUs(0);
                
                _tck.write(0);
                _delayUs(0);
                _tck.write(1);
                _delayUs(0);
            }
            
            // ## Reset JTAG state machine (test access port, TAP)
            _tapReset();
            
            // ## Validate the JTAG ID
            if (_readJTAGID() != _JTAGID) {
                mspprintf("AAA\r\n");
                continue; // Try again
            }
            
            // ## Check JTAG fuse blown state
            if (_readJTAGFuseBlown()) {
                mspprintf("BBB\r\n");
                // If the JTAG fuse is blown, we can only recover by erasing the device
                if (allowErase) {
                    mspprintf("Attempting erase\r\n");
                    _erase();
                    mspprintf("-> Done\r\n");
                }
                continue; // Try again
            }
            
            // ## Validate the Core ID
            if (_readCoreID() == 0) {
                mspprintf("CCC\r\n");
                continue; // Try again
            }
            
            // ## Validate the Device ID
            {
                // Set device into JTAG mode + read
                _shiftIR(_IR_CNTRL_SIG_16BIT);
                _shiftDR<16>(0x1501);
                
                // Wait until CPU is sync'd
                if (!_waitForCPUSync()) {
                    mspprintf("DDD\r\n");
                    continue;
                }
                
                // Reset CPU
                if (!_resetCPU()) {
                    mspprintf("EEE\r\n");
                    continue; // Try again
                }
                
                // Read device ID
                const uint32_t deviceIDAddr = _readDeviceIDAddr()+4;
                uint16_t deviceID = 0;
                _readMem(deviceIDAddr, &deviceID, 1);
                if (deviceID != _DeviceID) {
                    mspprintf("FFF\r\n");
                    continue; // Try again
                }
            }
            
            // Disable MPU (so we can write to FRAM)
            if (!_disableMPU()) {
                mspprintf("GGG\r\n");
                continue; // Try again
            }
            
            // Nothing failed!
            return true;
        }
        
        // Too many failures
        return false;
    }
    
    void disconnect() {
        // ## Disable test mode
        // Assert RST_
        _rst_.write(0);
        _delayMs(1);
        // Deassert TEST
        _test.write(0);
        _delayMs(1);
        // Deassert RST_
        _rst_.write(1);
        _delayMs(1);
    }
    
    void read(uint32_t addr, uint16_t* dst, uint32_t len) {
        _readMem(addr, dst, len);
    }
    
    void write(uint32_t addr, const uint16_t* src, uint32_t len) {
        if (!_crcValid) {
            _crc = addr-2;
            _crcValid = true;
        }
//        _writeMem(addr, src, len);
        _writeMem(addr, src, len);
    }
    
    void resetCRC() {
        _crcValid = false;
    }
    
    bool verifyCRC(uint32_t addr, uint32_t len) {
        return _crc == _calcCRC(addr, len);
    }
};

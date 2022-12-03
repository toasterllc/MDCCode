#pragma once
#include <msp430.h>

template <
typename T_Scheduler,
typename T_ClkPin,
typename T_DataPin,
typename T_Msg,
[[noreturn]] void T_Error(uint16_t)
>
class I2CType {
#define Assert(x) if (!(x)) T_Error(__LINE__)

public:
    struct Pin {
        using Clk       = typename T_ClkPin::template Opts<GPIO::Option::Sel01>;
        using Data      = typename T_DataPin::template Opts<GPIO::Option::Sel01>;
    };
    
    static void Init() {
        // Reset
        UCB0CTLW0 = UCSWRST;
        
        UCB0CTLW0 |=
            (UCA10&0)   |   // 7bit own addr
            (UCSLA10&0) |   // 7bit slave addr
            (UCMM&0)    |   // single-master
            (UCMST&0)   |   // slave mode
            UCMODE_3    |   // i2c mode
            UCSYNC      |   // (not applicable)
            UCSSEL_0    |   // (not applicable in slave mode)
            (UCTXACK&0) |   // (not applicable during setup)
            (UCTR&0)    |   // receiver mode
            UCTXNACK    |   // (not applicable during setup)
            UCTXSTP     |   // (not applicable in slave mode)
            UCTXSTT     |   // (not applicable in slave mode)
            (UCSWRST&0) ;   // already set UCSWRST bit above
        
        UCB0I2COA0 = 
            (UCGCEN&0)  |   // don't respond to general calls
            UCOAEN      |   // enable this slave (slave 0)
            0x55        ;   // our slave address
        
        // Enable!
        UCB0CTLW0 &= ~UCSWRST;
        
        
//#define UCBIT9IE               (0x4000)       /* I2C Bit 9 Position Interrupt Enable 3 */
//#define UCTXIE3                (0x2000)       /* I2C Transmit Interrupt Enable 3 */
//#define UCRXIE3                (0x1000)       /* I2C Receive Interrupt Enable 3 */
//#define UCTXIE2                (0x0800)       /* I2C Transmit Interrupt Enable 2 */
//#define UCRXIE2                (0x0400)       /* I2C Receive Interrupt Enable 2 */
//#define UCTXIE1                (0x0200)       /* I2C Transmit Interrupt Enable 1 */
//#define UCRXIE1                (0x0100)       /* I2C Receive Interrupt Enable 1 */
//#define UCCLTOIE               (0x0080)       /* I2C Clock Low Timeout interrupt enable */
//#define UCBCNTIE               (0x0040)       /* I2C Automatic stop assertion interrupt enable */
//#define UCNACKIE               (0x0020)       /* I2C NACK Condition interrupt enable */
//#define UCALIE                 (0x0010)       /* I2C Arbitration Lost interrupt enable */
//#define UCSTPIE                (0x0008)       /* I2C STOP Condition interrupt enable */
//#define UCSTTIE                (0x0004)       /* I2C START Condition interrupt enable */
//#define UCTXIE0                (0x0002)       /* I2C Transmit Interrupt Enable 0 */
//#define UCRXIE0                (0x0001)       /* I2C Receive Interrupt Enable 0 */
        
        
//        #warning TODO: in the future, we probably want UCSTTIE too, so that we can wake from sleep upon a START condition
//        // Enable interrupts
//        UCB0IE = (UCTXIE0 | UCRXIE0);
    }
    
    static void Recv(T_Msg& msg) {
        uint8_t* b = reinterpret_cast<uint8_t*>(&msg);
        
        uint16_t ev = _WaitForEvent();
        // Confirm that we have a START condition
        Assert(ev == USCI_I2C_UCSTTIFG);
        
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvent();
            // Confirm that we received another byte
            Assert(ev == USCI_I2C_UCRXIFG0);
            // Store the byte
            b[i] = UCB0RXBUF_L;
        }
        
        ev = _WaitForEvent();
        // Confirm that we have a STOP condition
        Assert(ev == USCI_I2C_UCSTPIFG);
    }
    
    static void Send(const T_Msg& msg) {
        
    }
    
    static void ISR() {
        // We should never be called until _Event is cleared
        Assert(!_Event);
        // Disable interrupts until current one is handled by our thread
        _I2CIntsSetEnabled(false);
        _Event = UCB0IV;
        
//        UCB0IV = ;
//        
//        switch (__even_in_range(UCB0IV, USCI_I2C_UCBIT9IFG)) {
////        case USCI_I2C_UCSTTIFG: // Start bit received
////            break;
////        case USCI_I2C_UCSTPIFG: // Stop bit received
////            break;
//        case USCI_I2C_UCRXIFG0:
//            // Disable receive interrupts until the current byte is handled
//            UCB0IE &= ~UCRXIE0;
//            _Rx = UCB0RXBUF;
//            break;
//        case USCI_I2C_UCTXIFG0:
//            break;
//        default:
//            // Received an interrupt we didn't enable
//            abort();
//            break;
//        }
        
//        #define USCI_I2C_UCALIFG       (0x0002)       /* Interrupt Vector: I2C Mode: UCALIFG */
//        #define USCI_I2C_UCNACKIFG     (0x0004)       /* Interrupt Vector: I2C Mode: UCNACKIFG */
//        #define USCI_I2C_UCSTTIFG      (0x0006)       /* Interrupt Vector: I2C Mode: UCSTTIFG*/
//        #define USCI_I2C_UCSTPIFG      (0x0008)       /* Interrupt Vector: I2C Mode: UCSTPIFG*/
//        #define USCI_I2C_UCRXIFG3      (0x000A)       /* Interrupt Vector: I2C Mode: UCRXIFG3 */
//        #define USCI_I2C_UCTXIFG3      (0x000C)       /* Interrupt Vector: I2C Mode: UCTXIFG3 */
//        #define USCI_I2C_UCRXIFG2      (0x000E)       /* Interrupt Vector: I2C Mode: UCRXIFG2 */
//        #define USCI_I2C_UCTXIFG2      (0x0010)       /* Interrupt Vector: I2C Mode: UCTXIFG2 */
//        #define USCI_I2C_UCRXIFG1      (0x0012)       /* Interrupt Vector: I2C Mode: UCRXIFG1 */
//        #define USCI_I2C_UCTXIFG1      (0x0014)       /* Interrupt Vector: I2C Mode: UCTXIFG1 */
//        #define USCI_I2C_UCRXIFG0      (0x0016)       /* Interrupt Vector: I2C Mode: UCRXIFG0 */
//        #define USCI_I2C_UCTXIFG0      (0x0018)       /* Interrupt Vector: I2C Mode: UCTXIFG0 */
//        #define USCI_I2C_UCBCNTIFG     (0x001A)       /* Interrupt Vector: I2C Mode: UCBCNTIFG */
//        #define USCI_I2C_UCCLTOIFG     (0x001C)       /* Interrupt Vector: I2C Mode: UCCLTOIFG */
//        #define USCI_I2C_UCBIT9IFG     (0x001E)       /* Interrupt Vector: I2C Mode: UCBIT9IFG */
        
        
        
//        case UCRXIFG0:
//        case UCTXIFG0:
//        
//        case 0x00: // Vector 0: No interrupts
//        break;
//        case 0x02: ... // Vector 2: ALIFG
//        break;
//        case 0x04: ... // Vector 4: NACKIFG
//        break;
//        case 0x06: ... // Vector 6: STTIFG
//        break;
//        case 0x08: ... // Vector 8: STPIFG
//        break;
//        case 0x0a: ... // Vector 10: RXIFG3
//        break;
//        case 0x0c: ... // Vector 12: TXIFG3
//        break;
//        case 0x0e: ... // Vector 14: RXIFG2
//        break;
//        case 0x10: ... // Vector 16: TXIFG2
//        break;
//        case 0x12: ... // Vector 18: RXIFG1
//        break;
//        case 0x14: ... // Vector 20: TXIFG1
//        break;
//        case 0x16: ... // Vector 22: RXIFG0
//        break;
//        case 0x18: ... // Vector 24: TXIFG0
//        break;
//        case 0x1a: ... // Vector 26: BCNTIFG
//        break;
//        case 0x1c: ... // Vector 28: clock low time-out
//        break;
//        case 0x1e: ... // Vector 30: 9th bit
//        break;
//        default: break;
    }

private:
    static void _I2CIntsSetEnabled(bool en) {
        if (en) UCB0IE = UCSTTIE | UCSTPIE | UCTXIE0 | UCRXIE0;
        else    UCB0IE = 0;
    }
//    static _RxSet(uint8_t b) {
//        // Disable receive interrupts until the current byte is handled
//        UCB0IE &= ~UCRXIE0;
//        _Rx = UCB0RXBUF;
//    }
    
    static uint16_t _WaitForEvent() {
        _Event = std::nullopt;
        // Re-enable interrupts now that we're ready for an event
        _I2CIntsSetEnabled(true);
        T_Scheduler::Wait([&] { return _Event.has_value(); });
        return *_Event;
    }
    
    static inline std::optional<uint16_t> _Event;

#undef Assert
};

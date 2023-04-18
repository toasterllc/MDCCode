#pragma once
#include "ICE.h"
#include "Assert.h"

namespace Img {

template <
typename T_Scheduler,
typename T_ICE
>
class Sensor {
public:
    static void Init() {
        // Toggle IMG_RST_
        {
            T_ICE::ImgReset();
        }
        
        // Wait 150k EXTCLK (16MHz) periods
        // (150e3*(1/16e6)) == 9.375ms
        // The docs say to wait 150k EXTCLK cycles, but empirically we've seen the subsequent I2C write
        // fail (responds with a NAK) if we only wait 10ms. We've also seen 11ms fail, so we bumped it
        // up to 15ms. See MDCNotes/AR0330-I2CNAK-After150k-EXTCLKs.png.
        #warning TODO: it's possible that the IMG reset was failing because the ICE message was being suppressed
        #warning TODO: because chip-select was already asserted when we sent the message (due to being in readout mode).
        #warning TODO: See commit 94bfa7b.
        #warning TODO: Therefore maybe we can switch back to 11ms? What about 10ms?
        {
            _Sleep(_Ms(15));
        }
        
        // Configure internal register initialization
        {
            T_ICE::ImgI2CWrite(0x3052, 0xA114);
        }
        
        // Start internal register initialization
        {
            T_ICE::ImgI2CWrite(0x304A, 0x0070);
        }
        
        // Wait 150k EXTCLK (16MHz) periods
        // (150e3*(1/16e6)) == 9.375ms
        {
            _Sleep(_Ms(10));
        }
        
        // Sanity-check pix comms by reading a known register
        {
            const uint16_t chipVersion = T_ICE::ImgI2CRead(0x3000);
            // TODO: we probably don't want to check the version number in production, in case the version number changes?
            // also the 0x3000 isn't read-only, so in theory it could change
            Assert(chipVersion == 0x2604);
        }
        
        // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
        // (Default value of 0x301A is 0x0058)
        {
            T_ICE::ImgI2CWrite(_ResetRegister::Address, _ResetRegister::Init);
        }
        
        // Set pre_pll_clk_div
        {
            T_ICE::ImgI2CWrite(0x302E, 4);        //  /4 (default)
        }
        
        // Set pll_multiplier
        {
            T_ICE::ImgI2CWrite(0x3030, 147);      //  *147
        }
        
        // Set vt_sys_clk_div
        {
            T_ICE::ImgI2CWrite(0x302C, 1);        //  /1 (default)
        }
        
        // Set vt_pix_clk_div
        {
            T_ICE::ImgI2CWrite(0x302A, 6);        //  /6 (default)
        }
        
    //        // Set op_pix_clk_div
    //        {
    //            T_ICE::ImgI2CWrite(0x3036, 0x000C);
    //        }
        
        // Set output slew rate
        {
    //        T_ICE::ImgI2CWrite(0x306E, 0x0010);  // Slow
    //        T_ICE::ImgI2CWrite(0x306E, 0x9010);  // Medium (default)
            T_ICE::ImgI2CWrite(0x306E, 0xFC10);  // Fast
        }
        
        // Set data_pedestal
        {
    //        T_ICE::ImgI2CWrite(0x301E, 0x00A8);  // Default
            T_ICE::ImgI2CWrite(0x301E, 0x0000);
        }
        
        // Set test data colors
        {
    //            // Set test_data_red
    //            T_ICE::ImgI2CWrite(0x3072, 0x0000);
    //            
    //            // Set test_data_greenr
    //            T_ICE::ImgI2CWrite(0x3074, 0x0000);
    //            
    //            // Set test_data_blue
    //            T_ICE::ImgI2CWrite(0x3076, 0x0000);
    //            
    //            // Set test_data_greenb
    //            T_ICE::ImgI2CWrite(0x3078, 0x0000);
                
    //            // Set test_data_red
    //            T_ICE::ImgI2CWrite(0x3072, 0x0B2A);  // AAA
    //            T_ICE::ImgI2CWrite(0x3072, 0x0FFF);  // FFF
    //    
    //            // Set test_data_greenr
    //            T_ICE::ImgI2CWrite(0x3074, 0x0C3B);  // BBB
    //            T_ICE::ImgI2CWrite(0x3074, 0x0FFF);  // FFF
    //            T_ICE::ImgI2CWrite(0x3074, 0x0000);
    //    
    //            // Set test_data_blue
    //            T_ICE::ImgI2CWrite(0x3076, 0x0D4C);  // CCC
    //            T_ICE::ImgI2CWrite(0x3076, 0x0FFF);  // FFF
    //            T_ICE::ImgI2CWrite(0x3076, 0x0000);
    //    
    //            // Set test_data_greenb
    //            T_ICE::ImgI2CWrite(0x3078, 0x0C3B);  // BBB
    //            T_ICE::ImgI2CWrite(0x3078, 0x0FFF);  // FFF
    //            T_ICE::ImgI2CWrite(0x3078, 0x0000);
            
        }
        
        // Set test_pattern_mode
        {
            // 0: Normal operation (generate output data from pixel array)
            // 1: Solid color test pattern.
            // 2: Full color bar test pattern
            // 3: Fade-to-gray color bar test pattern
            // 256: Walking 1s test pattern (12 bit)
    //        T_ICE::ImgI2CWrite(0x3070, 0x0000);  // Normal operation (default)
    //        T_ICE::ImgI2CWrite(0x3070, 0x0001);  // Solid color
    //        T_ICE::ImgI2CWrite(0x3070, 0x0002);  // Color bars
    //        T_ICE::ImgI2CWrite(0x3070, 0x0003);  // Fade-to-gray
    //        T_ICE::ImgI2CWrite(0x3070, 0x0100);  // Walking 1s
        }
        
        // Set serial_format
        // *** This register write is necessary for parallel mode.
        // *** The datasheet doesn't mention this. :(
        // *** Discovered looking at Linux kernel source.
        {
            T_ICE::ImgI2CWrite(0x31AE, 0x0301);
        }
        
        // Set data_format_bits
        // Datasheet:
        //   "The serial format should be configured using R0x31AC.
        //   This register should be programmed to 0x0C0C when
        //   using the parallel interface."
        {
            T_ICE::ImgI2CWrite(0x31AC, 0x0C0C);
        }
        
        // Set row_speed
        {
    //        T_ICE::ImgI2CWrite(0x3028, 0x0000);  // 0 cycle delay
    //        T_ICE::ImgI2CWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
        }

        // Set the x-start address
        {
    //        T_ICE::ImgI2CWrite(0x3004, 0x0006);  // Default
    //        T_ICE::ImgI2CWrite(0x3004, 0x0010);
        }

        // Set the x-end address
        {
    //        T_ICE::ImgI2CWrite(0x3008, 0x0905);  // Default
    //        T_ICE::ImgI2CWrite(0x3008, 0x01B1);
        }

        // Set the y-start address
        {
    //        T_ICE::ImgI2CWrite(0x3002, 0x007C);  // Default
    //        T_ICE::ImgI2CWrite(0x3002, 0x007C);
        }

        // Set the y-end address
        {
    //        T_ICE::ImgI2CWrite(0x3006, 0x058b);  // Default
    //        T_ICE::ImgI2CWrite(0x3006, 0x016B);
        }
        
        // Implement "Recommended Default Register Changes and Sequencer"
        {
            T_ICE::ImgI2CWrite(0x3ED2, 0x0146);
            T_ICE::ImgI2CWrite(0x3EDA, 0x88BC);
            T_ICE::ImgI2CWrite(0x3EDC, 0xAA63);
            T_ICE::ImgI2CWrite(0x305E, 0x00A0);
        }
        
        // Enable/disable embedded_data (2 extra rows of statistical info)
        // See AR0134_RR_D.pdf for info on statistics format
        {
    //            T_ICE::ImgI2CWrite(0x3064, 0x1902);  // Stats enabled (default)
            T_ICE::ImgI2CWrite(0x3064, 0x1802);  // Stats disabled
        }
    }
    
//    bool enabled() const { return _enabled; }
    
    static void SetStreamEnabled(bool en) {
        T_ICE::ImgI2CWrite(_ResetRegister::Address,
            _ResetRegister::Init | (en ? _ResetRegister::StreamEnable : 0));
    }
    
    static void SetCoarseIntTime(uint16_t coarseIntTime) {
        // Set coarse_integration_time
        T_ICE::ImgI2CWrite(0x3012, coarseIntTime);
    }
    
    static void SetFineIntTime(uint16_t fineIntTime) {
        // Set fine_integration_time
        T_ICE::ImgI2CWrite(0x3014, fineIntTime);
    }
    
    static void SetAnalogGain(uint16_t analogGain) {
        // Set analog_gain
        T_ICE::ImgI2CWrite(0x3060, analogGain);
    }
    
private:
    static constexpr auto _Ms = T_Scheduler::Ms;
    static constexpr auto _Sleep = T_Scheduler::Sleep;
    
    struct _ResetRegister {
        static constexpr uint16_t Address                   = 0x301A;
        
        static constexpr uint16_t SerialInterfaceDisable    = 1<<12;
        static constexpr uint16_t BadFrameRestart           = 1<<10;
        static constexpr uint16_t BadFrameMask              = 1<<9;
        static constexpr uint16_t ParallelInterfaceEnable   = 1<<7;
        static constexpr uint16_t StreamEnable              = 1<<2;
        
        static constexpr uint16_t Init                      = 0x0058                    |   // Default register value
                                                              ParallelInterfaceEnable   |
                                                              SerialInterfaceDisable    ;
    };
};

} // namespace Img

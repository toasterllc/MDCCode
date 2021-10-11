#pragma once
#include "SleepMs.h"

class ImgSensor {
public:
    // Functions provided by client
    static void Reset();
    static uint16_t I2CRead(uint16_t addr);
    static void I2CWrite(uint16_t addr, uint16_t val);
    
    static void Init() {
        // Power on and toggle IMG_RST_
        {
            Reset();
        }
        
        // Wait 150k EXTCLK (16MHz) periods
        // (150e3*(1/16e6)) == 9.375ms
        {
            SleepMs(10);
        }
        
        // Configure internal register initialization
        {
            I2CWrite(0x3052, 0xA114);
        }
        
        // Start internal register initialization
        {
            I2CWrite(0x304A, 0x0070);
        }
        
        // Wait 150k EXTCLK (16MHz) periods
        // (150e3*(1/16e6)) == 9.375ms
        {
            SleepMs(10);
        }
        
        // Sanity-check pix comms by reading a known register
        {
            const uint16_t chipVersion = I2CRead(0x3000);
            // TODO: we probably don't want to check the version number in production, in case the version number changes?
            // also the 0x3000 isn't read-only, so in theory it could change
            Assert(chipVersion == 0x2604);
        }
        
        // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
        // (Default value of 0x301A is 0x0058)
        {
            I2CWrite(0x301A, 0x10D8);
        }
        
        // Set pre_pll_clk_div
        {
            I2CWrite(0x302E, 4);        //  /4 (default)
        }
        
        // Set pll_multiplier
        {
            I2CWrite(0x3030, 147);      //  *147
        }
        
        // Set vt_sys_clk_div
        {
            I2CWrite(0x302C, 1);        //  /1 (default)
        }
        
        // Set vt_pix_clk_div
        {
            I2CWrite(0x302A, 6);        //  /6 (default)
        }
        
    //        // Set op_pix_clk_div
    //        {
    //            I2CWrite(0x3036, 0x000C);
    //        }
        
        // Set output slew rate
        {
    //        I2CWrite(0x306E, 0x0010);  // Slow
    //        I2CWrite(0x306E, 0x9010);  // Medium (default)
            I2CWrite(0x306E, 0xFC10);  // Fast
        }
        
        // Set data_pedestal
        {
    //        I2CWrite(0x301E, 0x00A8);  // Default
            I2CWrite(0x301E, 0x0000);
        }
        
        // Set test data colors
        {
    //            // Set test_data_red
    //            I2CWrite(0x3072, 0x0000);
    //            
    //            // Set test_data_greenr
    //            I2CWrite(0x3074, 0x0000);
    //            
    //            // Set test_data_blue
    //            I2CWrite(0x3076, 0x0000);
    //            
    //            // Set test_data_greenb
    //            I2CWrite(0x3078, 0x0000);
                
    //            // Set test_data_red
    //            I2CWrite(0x3072, 0x0B2A);  // AAA
    //            I2CWrite(0x3072, 0x0FFF);  // FFF
    //    
    //            // Set test_data_greenr
    //            I2CWrite(0x3074, 0x0C3B);  // BBB
    //            I2CWrite(0x3074, 0x0FFF);  // FFF
    //            I2CWrite(0x3074, 0x0000);
    //    
    //            // Set test_data_blue
    //            I2CWrite(0x3076, 0x0D4C);  // CCC
    //            I2CWrite(0x3076, 0x0FFF);  // FFF
    //            I2CWrite(0x3076, 0x0000);
    //    
    //            // Set test_data_greenb
    //            I2CWrite(0x3078, 0x0C3B);  // BBB
    //            I2CWrite(0x3078, 0x0FFF);  // FFF
    //            I2CWrite(0x3078, 0x0000);
            
        }
        
        // Set test_pattern_mode
        {
            // 0: Normal operation (generate output data from pixel array)
            // 1: Solid color test pattern.
            // 2: Full color bar test pattern
            // 3: Fade-to-gray color bar test pattern
            // 256: Walking 1s test pattern (12 bit)
    //        I2CWrite(0x3070, 0x0000);  // Normal operation (default)
    //        I2CWrite(0x3070, 0x0001);  // Solid color
    //        I2CWrite(0x3070, 0x0002);  // Color bars
    //        I2CWrite(0x3070, 0x0003);  // Fade-to-gray
    //        I2CWrite(0x3070, 0x0100);  // Walking 1s
        }
        
        // Set serial_format
        // *** This register write is necessary for parallel mode.
        // *** The datasheet doesn't mention this. :(
        // *** Discovered looking at Linux kernel source.
        {
            I2CWrite(0x31AE, 0x0301);
        }
        
        // Set data_format_bits
        // Datasheet:
        //   "The serial format should be configured using R0x31AC.
        //   This register should be programmed to 0x0C0C when
        //   using the parallel interface."
        {
            I2CWrite(0x31AC, 0x0C0C);
        }
        
        // Set row_speed
        {
    //        I2CWrite(0x3028, 0x0000);  // 0 cycle delay
    //        I2CWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
        }

        // Set the x-start address
        {
    //        I2CWrite(0x3004, 0x0006);  // Default
    //        I2CWrite(0x3004, 0x0010);
        }

        // Set the x-end address
        {
    //        I2CWrite(0x3008, 0x0905);  // Default
    //        I2CWrite(0x3008, 0x01B1);
        }

        // Set the y-start address
        {
    //        I2CWrite(0x3002, 0x007C);  // Default
    //        I2CWrite(0x3002, 0x007C);
        }

        // Set the y-end address
        {
    //        I2CWrite(0x3006, 0x058b);  // Default
    //        I2CWrite(0x3006, 0x016B);
        }
        
        // Implement "Recommended Default Register Changes and Sequencer"
        {
            I2CWrite(0x3ED2, 0x0146);
            I2CWrite(0x3EDA, 0x88BC);
            I2CWrite(0x3EDC, 0xAA63);
            I2CWrite(0x305E, 0x00A0);
        }
        
        // Enable/disable embedded_data (2 extra rows of statistical info)
        // See AR0134_RR_D.pdf for info on statistics format
        {
    //            I2CWrite(0x3064, 0x1902);  // Stats enabled (default)
            I2CWrite(0x3064, 0x1802);  // Stats disabled
        }
        
        constexpr uint16_t IntTimeMax = 16383;
        constexpr uint16_t GainMax = 63;
        
        constexpr uint16_t intTime = IntTimeMax/10;
        constexpr uint16_t gain = GainMax/10;
        
        // Set coarse_integration_time
        {
            // Normalize intTime to [0,IntTimeMax]
            constexpr uint16_t normVal = (((uint32_t)intTime*IntTimeMax)/UINT16_MAX);
            I2CWrite(0x3012, normVal);
        }
        
        // Set fine_integration_time
        {
            I2CWrite(0x3014, 0);
        }
        
        // Set analog_gain
        {
            // Normalize gain to [0,GainMax]
            constexpr uint16_t normVal = std::max((uint32_t)1, (((uint32_t)gain*GainMax)/UINT16_MAX));
            I2CWrite(0x3060, normVal);
        }
    }
    
    static void SetStreamEnabled(bool en) {
        I2CWrite(0x301A, (en ? 0x10DC : 0x10D8));
    }

};

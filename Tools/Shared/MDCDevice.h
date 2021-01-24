#pragma once
#include "USBDevice.h"
#include "USBInterface.h"
#include "USBPipe.h"
#include "SendRight.h"
#include "STAppTypes.h"
#include "TimeInstant.h"

class MDCDevice : public USBDevice {
public:
    using Milliseconds = uint32_t;
    
    static NSDictionary* MatchingDictionary() {
        return USBDevice::MatchingDictionary(1155, 57105);
    }
    
    static std::vector<MDCDevice> FindDevice() {
        return USBDevice::FindDevice<MDCDevice>(MatchingDictionary());
    }
    
    // Default constructor: empty
    MDCDevice() {}
    
    MDCDevice(SendRight&& service) :
    USBDevice(std::move(service)) {
        std::vector<USBInterface> interfaces = usbInterfaces();
        if (interfaces.size() != 1) throw std::runtime_error("invalid number of USB interfaces");
        _interface = interfaces[0];
        cmdOutPipe = USBPipe(_interface, STApp::EndpointIdxs::CmdOut);
        cmdInPipe = USBPipe(_interface, STApp::EndpointIdxs::CmdIn);
        pixInPipe = USBPipe(_interface, STApp::EndpointIdxs::PixIn);
    }
    
    void reset() const {
        // Send the reset vendor-defined control request
        vendorRequestOut(STApp::CtrlReqs::Reset, nullptr, 0);
        
        // Reset our pipes now that the device is reset
        for (const USBPipe& pipe : {cmdOutPipe, cmdInPipe, pixInPipe}) {
            pipe.reset();
        }
    }
    
    STApp::PixStatus pixStatus() const {
        using namespace STApp;
        Cmd cmd = { .op = Cmd::Op::PixGetStatus };
        cmdOutPipe.write(cmd);
        
        PixStatus pixStatus;
        cmdInPipe.read(pixStatus, 0);
        return pixStatus;
    }
    
    void pixReset() const {
        using namespace STApp;
        
        // Toggle the reset line
        {
            Cmd cmd = { .op = Cmd::Op::PixReset };
            cmdOutPipe.write(cmd);
            // Wait for completion by getting status
            pixStatus();
        }
        
        // Sanity-check pix comms by reading a known register
        {
            const uint16_t chipVersion = pixI2CRead(0x3000);
            // TODO: we probably don't want to check the version number in production, in case the version number changes?
            // also the 0x3000 isn't read-only, so in theory it could change
            assert(chipVersion == 0x2604);
        }
        
        // Configure internal register initialization
        {
            pixI2CWrite(0x3052, 0xA114);
        }
        
        // Start internal register initialization
        {
            pixI2CWrite(0x304A, 0x0070);
        }
        
        // Wait 150k EXTCLK (24MHz) periods
        // (150e3*(1/24e6)) == 6.25ms
        {
            usleep(7000);
        }
        
    }
    
    void pixConfig() const {
        // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
        // (Default value of 0x301A is 0x0058)
        {
            pixI2CWrite(0x301A, 0x10D8);
        }
        
        // Set pre_pll_clk_div
        {
//            pixI2CWrite(0x302E, 0x0002);  // /2 -> CLK_OP=98 MHz
            pixI2CWrite(0x302E, 0x0004);  // /4 -> CLK_OP=49 MHz (Default)
//            pixI2CWrite(0x302E, 0x0008);  // /8
//            pixI2CWrite(0x302E, 0x0020);  // /32
//            pixI2CWrite(0x302E, 0x003F);  // /63
        }
        
        // Set pll_multiplier
        {
            pixI2CWrite(0x3030, 0x0062);  // *98 (Default)
//            pixI2CWrite(0x3030, 0x0031);  // *49
        }
        
        // Set vt_pix_clk_div
        {
            pixI2CWrite(0x302A, 0x0006);  // /6 (Default)
//            pixI2CWrite(0x302A, 0x001F);  // /31
        }
        
        // Set op_pix_clk_div
        {
            pixI2CWrite(0x3036, 0x000C);
        }
        
        // Set output slew rate
        {
//            pixI2CWrite(0x306E, 0x0010);  // Slow
//            pixI2CWrite(0x306E, 0x9010);  // Medium (default)
            pixI2CWrite(0x306E, 0xFC10);  // Fast
        }
        
        // Set data_pedestal
        {
//            pixI2CWrite(0x301E, 0x00A8);  // Default
            pixI2CWrite(0x301E, 0x0000);
        }
        
        // Set test data colors
        {
//            // Set test_data_red
//            pixI2CWrite(0x3072, 0x0FFF);
//    
//            // Set test_data_greenr
//            pixI2CWrite(0x3074, 0x0FFF);
//    
//            // Set test_data_blue
//            pixI2CWrite(0x3076, 0x0FFF);
//    
//            // Set test_data_greenb
//            pixI2CWrite(0x3078, 0x0FFF);
            
//            // Set test_data_red
//            pixI2CWrite(0x3072, 0x0B2A);  // AAA
//            pixI2CWrite(0x3072, 0x0FFF);  // FFF
//    
//            // Set test_data_greenr
//            pixI2CWrite(0x3074, 0x0C3B);  // BBB
//            pixI2CWrite(0x3074, 0x0FFF);  // FFF
//            pixI2CWrite(0x3074, 0x0000);
//    
//            // Set test_data_blue
//            pixI2CWrite(0x3076, 0x0D4C);  // CCC
//            pixI2CWrite(0x3076, 0x0FFF);  // FFF
//            pixI2CWrite(0x3076, 0x0000);
//    
//            // Set test_data_greenb
//            pixI2CWrite(0x3078, 0x0C3B);  // BBB
//            pixI2CWrite(0x3078, 0x0FFF);  // FFF
//            pixI2CWrite(0x3078, 0x0000);
            
        }
        
        // Set test_pattern_mode
        {
            // 0: Normal operation (generate output data from pixel array)
            // 1: Solid color test pattern.
            // 2: Full color bar test pattern
            // 3: Fade-to-gray color bar test pattern
            // 256: Walking 1s test pattern (12 bit)
//            pixI2CWrite(0x3070, 0x0000);  // Normal operation
//            pixI2CWrite(0x3070, 0x0001);  // Solid color
            pixI2CWrite(0x3070, 0x0002);  // Color bars
//            pixI2CWrite(0x3070, 0x0003);  // Fade-to-gray
//            pixI2CWrite(0x3070, 0x0100);  // Walking 1s
        }
        
        // Set serial_format
        // *** This register write is necessary for parallel mode.
        // *** The datasheet doesn't mention this. :(
        // *** Discovered looking at Linux kernel source.
        {
            pixI2CWrite(0x31AE, 0x0301);
        }
        
        // Set data_format_bits
        // Datasheet:
        //   "The serial format should be configured using R0x31AC.
        //   This register should be programmed to 0x0C0C when
        //   using the parallel interface."
        {
            pixI2CWrite(0x31AC, 0x0C0C);
        }
        
        // Set row_speed
        {
//            pixI2CWrite(0x3028, 0x0000);  // 0 cycle delay
//            pixI2CWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
        }

        // Set the x-start address
        {
//            pixI2CWrite(0x3004, 0x0006);  // Default
//            pixI2CWrite(0x3004, 0x0010);
        }

        // Set the x-end address
        {
//            pixI2CWrite(0x3008, 0x0905);  // Default
//            pixI2CWrite(0x3008, 0x01B1);
        }

        // Set the y-start address
        {
//            pixI2CWrite(0x3002, 0x007C);  // Default
//            pixI2CWrite(0x3002, 0x007C);
        }

        // Set the y-end address
        {
//            pixI2CWrite(0x3006, 0x058b);  // Default
//            pixI2CWrite(0x3006, 0x016B);
        }
        
        // Implement "Recommended Default Register Changes and Sequencer"
        {
            pixI2CWrite(0x3ED2, 0x0146);
            pixI2CWrite(0x3EDA, 0x88BC);
            pixI2CWrite(0x3EDC, 0xAA63);
            pixI2CWrite(0x305E, 0x00A0);
        }
        
        // Enable/disable embedded_data (2 extra rows of statistical info)
        // See AR0134_RR_D.pdf for info on statistics format
        {
//            pixI2CWrite(0x3064, 0x1902);  // Stats enabled (default)
            pixI2CWrite(0x3064, 0x1802);  // Stats disabled
        }
        
        // Set coarse integration time
        {
//            pixI2CWrite(0x3012, 0x1000);
        }
        
        // Set line_length_pck
        {
//            pixI2CWrite(0x300C, 0x04E0);
        }
        
        // Start streaming
        // (Previous value of 0x301A is 0x10D8, as set above)
        {
            pixI2CWrite(0x301A, 0x10DC);
        }
    }
    
    uint16_t pixI2CRead(uint16_t addr) const {
        using namespace STApp;
        Cmd cmd = {
            .op = Cmd::Op::PixI2CTransaction,
            .arg = {
                .pixI2CTransaction = {
                    .write = false,
                    .addr = addr,
                }
            }
        };
        cmdOutPipe.write(cmd);
        PixStatus status = pixStatus();
        if (status.i2cErr) throw std::runtime_error("device reported i2c error");
        return status.i2cReadVal;
    }
    
    void pixI2CWrite(uint16_t addr, uint16_t val) const {
        using namespace STApp;
        Cmd cmd = {
            .op = Cmd::Op::PixI2CTransaction,
            .arg = {
                .pixI2CTransaction = {
                    .write = true,
                    .addr = addr,
                    .val = val,
                }
            }
        };
        cmdOutPipe.write(cmd);
        
        PixStatus status = pixStatus();
        if (status.i2cErr) throw std::runtime_error("device reported i2c error");
    }
    
    STApp::PixHeader pixCapture(STApp::Pixel* pixels, size_t cap, Milliseconds timeout=1000) const {
        using namespace STApp;
        Cmd cmd = {
            .op = Cmd::Op::PixCapture,
        };
        cmdOutPipe.write(cmd);
        
        PixHeader hdr;
        pixInPipe.read(hdr, timeout);
        
        const size_t imageLen = hdr.width*hdr.height*sizeof(Pixel);
        if (imageLen > cap)
            throw RuntimeError("buffer capacity too small (image length: %ju bytes, buffer capacity: %ju bytes)",
                (uintmax_t)imageLen, (uintmax_t)cap);
        
        pixInPipe.readBuf(pixels, imageLen, timeout);
        return hdr;
    }
    
//    void pixReadImage(STApp::Pixel* pixels, size_t count, Milliseconds timeout=0) const {
//        pixInPipe.readBuf(pixels, count*sizeof(STApp::Pixel), timeout);
//    }
    
    USBPipe cmdOutPipe;
    USBPipe cmdInPipe;
    USBPipe pixInPipe;
    
private:
    USBInterface _interface;
};

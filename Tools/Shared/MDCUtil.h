#include <vector>
#include <string>
#include <iostream>
#include <optional>
#include <inttypes.h>
#include "ELF32Binary.h"
#include "SendRight.h"
#include "USBDevice.h"
#include "USBInterface.h"
#include "USBPipe.h"
#include "STAppTypes.h"
#include "MyTime.h"
#include "RuntimeError.h"
#include "MDCDevice.h"

class MDCUtil {
public:
    using Cmd = std::string;
    struct Args {
        Cmd cmd;
        
        struct {
            bool write;
            uint16_t addr;
            uint16_t val;
        } pixI2C;
        
        struct {
            uint8_t idx;
            uint8_t on;
        } ledSet;
    };
    
    static Args ParseArgs(const std::vector<std::string>& strs) {
        Args args;
        if (strs.size() < 1) throw std::runtime_error("no command specified");
        args.cmd = strs[0];
        
        if (args.cmd == _PixResetCmd) {
            
        } else if (args.cmd == _PixConfigCmd) {
            
        } else if (args.cmd == _PixI2CCmd) {
            if (strs.size() < 2) throw std::runtime_error("no register specified");
            std::stringstream ss(strs[1]);
            std::string part;
            std::vector<std::string> parts;
            while (std::getline(ss, part, '=')) parts.push_back(part);
            
            uintmax_t addr = strtoumax(parts[0].c_str(), nullptr, 0);
            if (addr > UINT16_MAX) throw std::runtime_error("invalid register address");
            args.pixI2C.addr = addr;
            
            args.pixI2C.write = parts.size()>1;
            if (args.pixI2C.write) {
                uintmax_t val = strtoumax(parts[1].c_str(), nullptr, 0);
                if (val > UINT16_MAX) throw std::runtime_error("invalid register value");
                args.pixI2C.val = val;
            }
        
        } else if (args.cmd == _PixStreamCmd) {
        
        } else if (args.cmd == _LEDSetCmd) {
            if (strs.size() < 3) throw std::runtime_error("LED index/state not specified");
            args.ledSet.idx = std::stoi(strs[1]);
            args.ledSet.on = std::stoi(strs[2]);
        
        } else if (args.cmd == _TestResetStreamCmd) {
        
        } else if (args.cmd == _TestResetStreamIncCmd) {
        
        } else {
            throw std::runtime_error("invalid command");
        }
        
        return args;
    }
    
    static void PrintUsage() {
        using namespace std;
        cout << "MDCUtil commands:\n";
        cout << "  " << _PixResetCmd            << "\n";
        cout << "  " << _PixConfigCmd           << "\n";
        cout << "  " << _PixI2CCmd              << "\n";
        cout << "  " << _PixStreamCmd           << "\n";
        cout << "  " << _LEDSetCmd              << " <idx> <0/1>\n";
        cout << "  " << _TestResetStreamCmd     << "\n";
        cout << "  " << _TestResetStreamIncCmd  << "\n";
        cout << "\n";
    }
    
    static void Run(MDCDevice& device, const Args& args) {
        // Reset the device to put it back in a pre-defined state
        device.reset();
        
        try {
                 if (args.cmd == _PixResetCmd)              _PixReset(args, device);
            else if (args.cmd == _PixConfigCmd)             _PixConfig(args, device);
            else if (args.cmd == _PixI2CCmd)                _PixI2C(args, device);
            else if (args.cmd == _PixStreamCmd)             _PixStream(args, device);
            else if (args.cmd == _LEDSetCmd)                _LEDSet(args, device);
            else if (args.cmd == _TestResetStreamCmd)       _TestResetStream(args, device);
            else if (args.cmd == _TestResetStreamIncCmd)    _TestResetStreamInc(args, device);
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Error: %s\n\n", e.what());
            return;
        }
    }
    
    static const inline Cmd _PixResetCmd            = "PixReset";
    static const inline Cmd _PixConfigCmd           = "PixConfig";
    static const inline Cmd _PixI2CCmd              = "PixI2C";
    static const inline Cmd _PixStreamCmd           = "PixStream";
    static const inline Cmd _LEDSetCmd              = "LEDSet";
    static const inline Cmd _TestResetStreamCmd     = "TestResetStream";
    static const inline Cmd _TestResetStreamIncCmd  = "TestResetStreamInc";
    
    static void _PixReset(const Args& args, MDCDevice& device) {
        using namespace STApp;
        device.pixReset();
        
        // Sanity-check pix comms by reading a known register
        {
            const uint16_t chipVersion = device.pixI2CRead(0x3000);
            // TODO: we probably don't want to check the version number in production, in case the version number changes?
            // also the 0x3000 isn't read-only, so in theory it could change
            assert(chipVersion == 0x2604);
        }
        
        // Configure internal register initialization
        {
            device.pixI2CWrite(0x3052, 0xA114);
        }
        
        // Start internal register initialization
        {
            device.pixI2CWrite(0x304A, 0x0070);
        }
        
        // Wait 150k EXTCLK (24MHz) periods
        // (150e3*(1/24e6)) == 6.25ms
        {
            usleep(7000);
        }
    }
    
    static void _PixConfig(const Args& args, MDCDevice& device) {
        // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
        // (Default value of 0x301A is 0x0058)
        {
            device.pixI2CWrite(0x301A, 0x10D8);
        }
        
        // Set pre_pll_clk_div
        {
//            device.pixI2CWrite(0x302E, 0x0002);  // /2 -> CLK_OP=98 MHz
            device.pixI2CWrite(0x302E, 0x0004);  // /4 -> CLK_OP=49 MHz (Default)
//            device.pixI2CWrite(0x302E, 0x0008);  // /8
//            device.pixI2CWrite(0x302E, 0x0020);  // /32
//            device.pixI2CWrite(0x302E, 0x003F);  // /63
        }
        
        // Set pll_multiplier
        {
            device.pixI2CWrite(0x3030, 0x0062);  // *98 (Default)
//            device.pixI2CWrite(0x3030, 0x0031);  // *49
        }
        
        // Set vt_pix_clk_div
        {
            device.pixI2CWrite(0x302A, 0x0006);  // /6 (Default)
//            device.pixI2CWrite(0x302A, 0x001F);  // /31
        }
        
        // Set op_pix_clk_div
        {
            device.pixI2CWrite(0x3036, 0x000C);
        }
        
        // Set output slew rate
        {
//            device.pixI2CWrite(0x306E, 0x0010);  // Slow
//            device.pixI2CWrite(0x306E, 0x9010);  // Medium (default)
            device.pixI2CWrite(0x306E, 0xFC10);  // Fast
        }
        
        // Set data_pedestal
        {
//            device.pixI2CWrite(0x301E, 0x00A8);  // Default
//            device.pixI2CWrite(0x301E, 0x0000);
        }
        
        // Set test data colors
        {
//            // Set test_data_red
//            device.pixI2CWrite(0x3072, 0x0B2A);  // AAA
//            device.pixI2CWrite(0x3072, 0x0FFF);  // FFF
//    
//            // Set test_data_greenr
//            device.pixI2CWrite(0x3074, 0x0C3B);  // BBB
//            device.pixI2CWrite(0x3074, 0x0FFF);  // FFF
//            device.pixI2CWrite(0x3074, 0x0000);
//    
//            // Set test_data_blue
//            device.pixI2CWrite(0x3076, 0x0D4C);  // CCC
//            device.pixI2CWrite(0x3076, 0x0FFF);  // FFF
//            device.pixI2CWrite(0x3076, 0x0000);
//    
//            // Set test_data_greenb
//            device.pixI2CWrite(0x3078, 0x0C3B);  // BBB
//            device.pixI2CWrite(0x3078, 0x0FFF);  // FFF
//            device.pixI2CWrite(0x3078, 0x0000);
            
        }
        
        // Set test_pattern_mode
        {
            // 0: Normal operation (generate output data from pixel array)
            // 1: Solid color test pattern.
            // 2: Full color bar test pattern
            // 3: Fade-to-gray color bar test pattern
            // 256: Walking 1s test pattern (12 bit)
            device.pixI2CWrite(0x3070, 0x0000);  // Normal operation
//            device.pixI2CWrite(0x3070, 0x0001);  // Solid color
//            device.pixI2CWrite(0x3070, 0x0002);  // Color bars
//            device.pixI2CWrite(0x3070, 0x0003);  // Fade-to-gray
//            device.pixI2CWrite(0x3070, 0x0100);  // Walking 1s
        }
        
        // Set serial_format
        // *** This register write is necessary for parallel mode.
        // *** The datasheet doesn't mention this. :(
        // *** Discovered looking at Linux kernel source.
        {
            device.pixI2CWrite(0x31AE, 0x0301);
        }
        
        // Set data_format_bits
        // Datasheet:
        //   "The serial format should be configured using R0x31AC.
        //   This register should be programmed to 0x0C0C when
        //   using the parallel interface."
        {
            device.pixI2CWrite(0x31AC, 0x0C0C);
        }
        
        // Set row_speed
        {
//            device.pixI2CWrite(0x3028, 0x0000);  // 0 cycle delay
//            device.pixI2CWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
        }

        // Set the x-start address
        {
//            device.pixI2CWrite(0x3004, 0x0006);  // Default
//            device.pixI2CWrite(0x3004, 0x0010);
        }

        // Set the x-end address
        {
//            device.pixI2CWrite(0x3008, 0x0905);  // Default
//            device.pixI2CWrite(0x3008, 0x01B1);
        }

        // Set the y-start address
        {
//            device.pixI2CWrite(0x3002, 0x007C);  // Default
//            device.pixI2CWrite(0x3002, 0x007C);
        }

        // Set the y-end address
        {
//            device.pixI2CWrite(0x3006, 0x058b);  // Default
//            device.pixI2CWrite(0x3006, 0x016B);
        }
        
        // Implement "Recommended Default Register Changes and Sequencer"
        {
            device.pixI2CWrite(0x3ED2, 0x0146);
            device.pixI2CWrite(0x3EDA, 0x88BC);
            device.pixI2CWrite(0x3EDC, 0xAA63);
            device.pixI2CWrite(0x305E, 0x00A0);
        }
        
        // Disable embedded_data (first 2 rows of statistic info)
        // See AR0134_RR_D.pdf for info on statistics format
        {
//            device.pixI2CWrite(0x3064, 0x1902);  // Stats enabled (default)
            device.pixI2CWrite(0x3064, 0x1802);  // Stats disabled
        }
        
        // Set coarse integration time
        {
//            device.pixI2CWrite(0x3012, 0x1000);
        }
        
        // Set line_length_pck
        {
//            device.pixI2CWrite(0x300C, 0x04E0);
        }
        
        // Start streaming
        // (Previous value of 0x301A is 0x10D8, as set above)
        {
            device.pixI2CWrite(0x301A, 0x10DC);
        }
    }
    
    static void _PixI2C(const Args& args, MDCDevice& device) {
        using namespace STApp;
        
        if (args.pixI2C.write) {
            device.pixI2CWrite(args.pixI2C.addr, args.pixI2C.val);
        
        } else {
            const uint16_t val = device.pixI2CRead(args.pixI2C.addr);
            printf("0x%04x = 0x%04x\n", args.pixI2C.addr, val);
        }
    }
    
    static void _PixStream(const Args& args, MDCDevice& device) {
        using namespace STApp;
        const PixStatus pixStatus = device.pixStatus();
        const size_t pixelCount = pixStatus.width*pixStatus.height;
        
        // Start Pix stream
        device.pixStartStream();
        
        auto pixels = std::make_unique<Pixel[]>(pixelCount);
        for (;;) {
            device.pixReadImage(pixels.get(), pixelCount);
            printf("Got %ju pixels (%ju x %ju)\n",
                (uintmax_t)pixelCount, (uintmax_t)pixStatus.width, (uintmax_t)pixStatus.height);
        }
    }
    
    static void _LEDSet(const Args& args, MDCDevice& device) {
        using namespace STApp;
        
        STApp::Cmd cmd = {
            .op = STApp::Cmd::Op::LEDSet,
            .arg = {
                .ledSet = {
                    .idx = args.ledSet.idx,
                    .on = args.ledSet.on,
                },
            },
        };
        
        device.cmdOutPipe.write(cmd);
    }
    
    static void _TestResetStream(const Args& args, MDCDevice& device) {
        // TODO: for this to work we need to enable a test mode on the device, and fill the first byte of every transfer with a counter
        using namespace STApp;
        
        // Get Pix info
        const PixStatus pixStatus = device.pixStatus();
        const size_t pixelCount = pixStatus.width*pixStatus.height;
        auto pixels = std::make_unique<Pixel[]>(pixelCount);
        for (;;) {
            // Start Pix stream
            device.pixStartStream();
            
            // Read data and make sure it's synchronized (by making
            // sure it starts with the magic number)
            printf("Reading from PixIn...\n");
            for (int i=0; i<3; i++) {
                device.pixReadImage(pixels.get(), pixelCount);
                uint32_t magicNum = 0;
                memcpy(&magicNum, pixels.get(), sizeof(magicNum));
                if (magicNum != PixTestMagicNumber) throw std::runtime_error("invalid magic number");
            }
            printf("-> Done\n\n");
            
            // De-synchronize the data by performing a truncated read
            printf("Corrupting PixIn endpoint...\n");
            for (int i=0; i<3; i++) {
                uint8_t buf[512];
                device.pixInPipe.read(buf, sizeof(buf));
            }
            printf("-> Done\n\n");
            
            // Recover device
            printf("Recovering device...\n");
            device.reset();
            printf("-> Done\n\n");
        }
    }
    
    static void _TestResetStreamInc(const Args& args, MDCDevice& device) {
        // TODO: for this to work we need to enable a test mode on the device, and fill the first byte of every transfer with a counter
        using namespace STApp;
        
        // Get Pix info
        const PixStatus pixStatus = device.pixStatus();
        const size_t pixelCount = pixStatus.width*pixStatus.height;
        auto pixels = std::make_unique<Pixel[]>(pixelCount);
        for (;;) {
            // Start Pix stream
            device.pixStartStream();
            
            // Read data and make sure it's synchronized (by making
            // sure it starts with the magic number)
            printf("Reading from PixIn...\n");
            for (int i=0; i<3; i++) {
                device.pixReadImage(pixels.get(), pixelCount);
                uint32_t magicNum = 0;
                memcpy(&magicNum, pixels.get(), sizeof(magicNum));
                if (magicNum != PixTestMagicNumber) throw std::runtime_error("invalid magic number");
                
                // Verify that the values are incrementing numbers
                std::optional<uint16_t> lastNum;
                // Start off past the magic number
                for (size_t i=2; i<pixelCount; i++) {
                    const uint16_t num = pixels[i];
                    if (lastNum) {
                        uint16_t expected = *lastNum+1;
                        if (num != expected) {
                            throw RuntimeError("invalid number; expected: 0x%04x, got: 0x%04x", expected, num);
                        }
                    }
                    lastNum = num;
                }
            }
            printf("-> Done\n\n");
            
            // De-synchronize the data by performing a truncated read
            printf("Corrupting PixIn endpoint...\n");
            for (int i=0; i<3; i++) {
                uint8_t buf[512];
                device.pixInPipe.read(buf, sizeof(buf));
            }
            printf("-> Done\n\n");
            
            // Recover device
            printf("Recovering device...\n");
            device.reset();
            printf("-> Done\n\n");
        }
    }

};

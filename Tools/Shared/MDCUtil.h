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
            
        } else if (args.cmd == _PixI2CCmd) {
            if (strs.size() < 2) throw std::runtime_error("no register specified");
            std::stringstream ss(strs[1]);
            std::string part;
            std::vector<std::string> parts;
            while (std::getline(ss, part, '=')) parts.push_back(part);
            
            uintmax_t addr = strtoumax(parts[0].c_str(), nullptr, 0);
            if (addr > UINT16_MAX) throw std::runtime_error("invalid register address");
            args.pixI2C.addr = addr;
            
            if (parts.size() > 1) {
                uintmax_t val = strtoumax(parts[1].c_str(), nullptr, 0);
                if (val > UINT16_MAX) throw std::runtime_error("invalid register value");
                args.pixI2C.write = true;
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
    
private:
    
    static const inline Cmd _PixResetCmd            = "PixReset";
    static const inline Cmd _PixI2CCmd              = "PixI2C";
    static const inline Cmd _PixStreamCmd           = "PixStream";
    static const inline Cmd _LEDSetCmd              = "LEDSet";
    static const inline Cmd _TestResetStreamCmd     = "TestResetStream";
    static const inline Cmd _TestResetStreamIncCmd  = "TestResetStreamInc";
    
    static void _PixReset(const Args& args, MDCDevice& device) {
        using namespace STApp;
        device.pixReset();
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

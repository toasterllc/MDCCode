#import "MDCMainView.h"
#import <memory>
#import "MDCImageLayer.h"
#import "STAppTypes.h"
#import "MDCDevice.h"
#import <iostream>
#import "MDCUtil.h"
using namespace MDCImageLayerTypes;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

enum class StreamState {
    Idle,
    Streaming,
    Stopped,
};

@implementation AppDelegate {
    IBOutlet MDCMainView* _mainView;
    MDCDevice _device;
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        StreamState streamState = StreamState::Idle;
        bool streamCancel = false;
    } _state;
}

//static bool checkPixel(uint32_t x, uint32_t y, ImagePixel expected, ImagePixel got) {
//    if (got != expected) {
//        printf("Pixel {%5ju,%5ju}: expected=%03jx, got=%03jx\n",
//            (uintmax_t)x, (uintmax_t)y, (uintmax_t)expected, (uintmax_t)got);
//        return false;
//    }
//    return true;
//}

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    std::vector<MDCDevice> devices = MDCDevice::FindDevices();
    if (devices.empty()) throw std::runtime_error("no matching MDC devices");
    if (devices.size() > 1) throw std::runtime_error("too many matching MDC devices");
    _device = devices[0];
    
    [NSThread detachNewThreadWithBlock:^{
        [self _threadControl];
    }];
}

static void _pixConfig(MDCDevice& device) {
    {
        // Reset the image sensor
        device.pixReset();
    }
    
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
    
    // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
    // (Default value of 0x301A is 0x0058)
    {
        device.pixI2CWrite(0x301A, 0x10D8);
    }
    
    // Set pre_pll_clk_div
    {
//        device.pixI2CWrite(0x302E, 0x0002);  // /2 -> CLK_OP=98 MHz
        device.pixI2CWrite(0x302E, 0x0004);  // /4 -> CLK_OP=49 MHz (Default)
//        device.pixI2CWrite(0x302E, 0x0008);  // /8
//        device.pixI2CWrite(0x302E, 0x0020);  // /32
//        device.pixI2CWrite(0x302E, 0x003F);  // /63
    }
    
    // Set pll_multiplier
    {
//        device.pixI2CWrite(0x3030, 0x0062);  // *98 (Default)
//        device.pixI2CWrite(0x3030, 0x0062);  // *98 (Default)
        device.pixI2CWrite(0x3030, 0x0031);  // *49
    }
    
    // Set vt_pix_clk_div
    {
        device.pixI2CWrite(0x302A, 0x0006);  // /6 (Default)
//        device.pixI2CWrite(0x302A, 0x001F);  // /31
    }
    
    // Set op_pix_clk_div
    {
        device.pixI2CWrite(0x3036, 0x000A);
    }
    
    // Set output slew rate
    {
//        device.pixI2CWrite(0x306E, 0x0010);  // Slow
//        device.pixI2CWrite(0x306E, 0x9010);  // Medium (default)
        device.pixI2CWrite(0x306E, 0xFC10);  // Fast
    }
    
    // Set data_pedestal
    {
//        device.pixI2CWrite(0x301E, 0x00A8);  // Default
//        device.pixI2CWrite(0x301E, 0x0000);
    }
    
    // Set test data colors
    {
//        // Set test_data_red
//        device.pixI2CWrite(0x3072, 0x0B2A);  // AAA
//        device.pixI2CWrite(0x3072, 0x0FFF);  // FFF
//
//        // Set test_data_greenr
//        device.pixI2CWrite(0x3074, 0x0C3B);  // BBB
//        device.pixI2CWrite(0x3074, 0x0FFF);  // FFF
//        device.pixI2CWrite(0x3074, 0x0000);
//
//        // Set test_data_blue
//        device.pixI2CWrite(0x3076, 0x0D4C);  // CCC
//        device.pixI2CWrite(0x3076, 0x0FFF);  // FFF
//        device.pixI2CWrite(0x3076, 0x0000);
//
//        // Set test_data_greenb
//        device.pixI2CWrite(0x3078, 0x0C3B);  // BBB
//        device.pixI2CWrite(0x3078, 0x0FFF);  // FFF
//        device.pixI2CWrite(0x3078, 0x0000);
        
        
//        device.pixI2CWrite(0x3072, 0x0000);
//        device.pixI2CWrite(0x3074, 0x0000);
//        device.pixI2CWrite(0x3076, 0x0FFF);
//        device.pixI2CWrite(0x3078, 0x0000);
        
    }
    
    // Set test_pattern_mode
    {
        // 0: Normal operation (generate output data from pixel array)
        // 1: Solid color test pattern.
        // 2: Full color bar test pattern
        // 3: Fade-to-gray color bar test pattern
        // 256: Walking 1s test pattern (12 bit)
        device.pixI2CWrite(0x3070, 0x0000);  // Normal operation
//        device.pixI2CWrite(0x3070, 0x0001);  // Solid color
//        device.pixI2CWrite(0x3070, 0x0002);  // Color bars
//        device.pixI2CWrite(0x3070, 0x0003);  // Fade-to-gray
//        device.pixI2CWrite(0x3070, 0x0100);  // Walking 1s
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
//        device.pixI2CWrite(0x3028, 0x0000);  // 0 cycle delay
//        device.pixI2CWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
    }

    // Set the x-start address
    {
//        device.pixI2CWrite(0x3004, 0x0006);  // Default
//        device.pixI2CWrite(0x3004, 0x0010);
    }

    // Set the x-end address
    {
//        device.pixI2CWrite(0x3008, 0x0905);  // Default
//        device.pixI2CWrite(0x3008, 0x01B1);
    }

    // Set the y-start address
    {
//        device.pixI2CWrite(0x3002, 0x007C);  // Default
//        device.pixI2CWrite(0x3002, 0x007C);
    }

    // Set the y-end address
    {
//        device.pixI2CWrite(0x3006, 0x058b);  // Default
//        device.pixI2CWrite(0x3006, 0x016B);
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
//        device.pixI2CWrite(0x3064, 0x1902);  // Stats enabled (default)
        device.pixI2CWrite(0x3064, 0x1802);  // Stats disabled
    }
    
    // Set coarse integration time
    {
        device.pixI2CWrite(0x3012, 0x1000);
    }
    
    // Set line_length_pck
    {
//        device.pixI2CWrite(0x300C, 0x04E0);
        device.pixI2CWrite(0x300C, 0x04E0);
    }
    
    // Start streaming
    // (Previous value of 0x301A is 0x10D8, as set above)
    {
        device.pixI2CWrite(0x301A, 0x10DC);
    }
}

- (void)_threadControl {
    for (;;) {
        // Kick off a new streaming thread
        _state.lock.lock();
            _state.streamState = StreamState::Streaming;
            _state.streamCancel = false;
            _state.signal.notify_all();
        _state.lock.unlock();
        
        [NSThread detachNewThreadWithBlock:^{
            [self _threadStreamImages];
        }];
        
        // Read arguments from stdin
        std::string line;
        std::getline(std::cin, line);
        
        std::vector<std::string> argStrs;
        std::stringstream argStream(line);
        std::string argStr;
        while (std::getline(argStream, argStr, ' ')) {
            if (!argStr.empty()) argStrs.push_back(argStr);
        }
        
        // Parse arguments
        MDCUtil::Args args;
        try {
            args = MDCUtil::ParseArgs(argStrs);
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Bad arguments: %s\n\n", e.what());
            MDCUtil::PrintUsage();
            continue;
        }
        
        // Cancel streaming and wait for it to stop
        for (;;) {
            auto lock = std::unique_lock(_state.lock);
            if (_state.streamState == StreamState::Streaming) {
                _state.streamCancel = true;
            }
            if (_state.streamState==StreamState::Idle ||
                _state.streamState==StreamState::Stopped) break;
            _state.signal.wait(lock);
        }
        
        try {
            std::vector<MDCDevice> devices = MDCDevice::FindDevices();
            if (devices.empty()) throw RuntimeError("no matching MDC devices");
            if (devices.size() > 1) throw RuntimeError("Too many matching MDC devices");
            
            MDCUtil::Run(devices[0], args);
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Error: %s\n\n", e.what());
            continue;
        }
    }
}

- (void)_threadStreamImages {
    using namespace STApp;
    
    MDCImageLayer* layer = [_mainView layer];
    
    // Reset the device to put it back in a pre-defined state
    _device.reset();
    
    // Configure the image sensor
    _pixConfig(_device);
    
    const PixStatus pixStatus = _device.pixStatus();
    // Start Pix stream
    _device.pixStartStream();
    
    const size_t pixelCount = pixStatus.width*pixStatus.height;
    auto pixels = std::make_unique<Pixel[]>(pixelCount);
    for (;;) {
        try {
            // Check if we've been cancelled
            bool cancel = false;
            _state.lock.lock();
                cancel = _state.streamCancel;
            _state.lock.unlock();
            if (cancel) break;
            
            // Read an image, timing-out after 1s so we can check the device status,
            // in case it reports a streaming error
            _device.pixReadImage(pixels.get(), pixelCount, 1000);
//            printf("Got %ju pixels (%ju x %ju)\n",
//                (uintmax_t)pixelCount, (uintmax_t)pixStatus.width, (uintmax_t)pixStatus.height);
            
            Image image = {
                .width = pixStatus.width,
                .height = pixStatus.height,
                .pixels = pixels.get(),
            };
            [layer updateImage:image];
        
        } catch (...) {
            if (_device.pixStatus().state != PixState::Streaming) {
//                printf("pixStatus.state != PixState::Streaming\n");
                break;
            }
        }
    }
    
    // Notify that our thread has exited
    _state.lock.lock();
        _state.streamState = StreamState::Stopped;
        _state.signal.notify_all();
    _state.lock.unlock();
}

@end

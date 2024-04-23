#import "AppDelegate.h"
#import <vector>
#import <thread>
#import <QuartzCore/QuartzCore.h>
#import "MDCUSBDevice.h"

@interface PlotLayer : CALayer
@end

@implementation PlotLayer {
    std::vector<CALayer*> _points;
    std::thread _usbThread;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
//    [self setBackgroundColor:[[NSColor redColor] CGColor]];
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
        [self _pointAdd];
    }];
    
    _usbThread = std::thread([=]{
        [self _usbThread];
    });
    
//    [self _pointAdd];
    return self;
}

- (void)_usbThread {
    std::vector<MDCUSBDevicePtr> devices;
    try {
        devices = MDCUSBDevice::GetDevices();
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to get MDC loader devices: %s\n\n", e.what());
        return 1;
    }
    
    if (devices.empty()) {
        fprintf(stderr, "No matching MDC devices\n\n");
        return 1;
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching MDC devices\n\n");
        return 1;
    }
    
    MDCUSBDevice& device = *(devices[0]);
    
    
    
    static_assert(!(SD::BlockLen % Toastbox::USB::Endpoint::MaxPacketSizeBulk));
    const size_t len = (size_t)args.SDRead.count * (size_t)SD::BlockLen;
    
    printf("Sending SDInit command...\n");
    device.sdInit();
    printf("-> OK\n\n");
    
    printf("Sending SDRead command...\n");
    device.sdRead(args.SDRead.addr);
    printf("-> OK\n\n");
    
    printf("Reading data...\n");
    
    for (;;) {
        auto buf = std::make_unique<uint8_t[]>(len);
        auto timeStart = std::chrono::steady_clock::now();
        device.readout(buf.get(), len);
        auto duration = std::chrono::steady_clock::now() - timeStart;
        auto durationUs = std::chrono::duration_cast<std::chrono::microseconds>(duration);
        const float throughputMBPerSec = (((double)(len*(uint64_t)1000000)) / durationUs.count()) / (1024*1024);
        printf("-> OK (throughput: %.1f MB/sec)\n\n", throughputMBPerSec);
    }
}

- (void)_pointAdd {
    CALayer* point = [CALayer new];
    [point setBackgroundColor:[[NSColor darkGrayColor] CGColor]];
    
    const CGFloat boundsWidth = [self bounds].size.width;
    
    const CGFloat size = 5;
    [point setFrame:{0,0,size,size}];
    [point setCornerRadius:size/2];
//    [point setPosition:{boundsWidth,50}];
    [self addSublayer:point];
    
    CABasicAnimation* anim = [CABasicAnimation animationWithKeyPath:@"position"];
    [anim setFromValue:[NSValue valueWithPoint:{boundsWidth, 50}]];
    [anim setToValue:[NSValue valueWithPoint:{0, 50}]];
    [anim setDuration:100];
    [point addAnimation:anim forKey:@"position"];
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:false block:^(NSTimer* timer) {
//        CABasicAnimation* anim = [CABasicAnimation animationWithKeyPath:@"position"];
//        [anim setFromValue:[NSValue valueWithPoint:{boundsWidth, 50}]];
//        [anim setToValue:[NSValue valueWithPoint:{0, 50}]];
//        [anim setDuration:5];
//        [point addAnimation:anim forKey:@"position"];
//    }];
    
//    let animation = CABasicAnimation(keyPath: "position")
//    animation.fromValue = [0, 0]
//    animation.toValue = [100, 100]
    
    
//    let animation = [CABasicAnimation keyPath: "backgroundColor")
//    animation.fromValue = NSColor.red.cgColor
//    animation.toValue = NSColor.blue.cgColor
    
//    [CABasi]
    
//    [CATransaction begin];
    
}

@end

@implementation AppDelegate {
    IBOutlet NSView* _mainView;
    IBOutlet NSWindow* window;
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    [_mainView setLayer:[PlotLayer new]];
}

@end

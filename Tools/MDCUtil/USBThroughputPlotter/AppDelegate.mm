#import "AppDelegate.h"
#import "MDCUSBDevice.h"
#import <thread>
#import <vector>
#import <QuartzCore/QuartzCore.h>
#import "Code/Lib/Toastbox/Mac/Util.h"

@interface PlotLayer : CALayer
@end

@implementation PlotLayer {
@public
    std::vector<CALayer*> _points;
    std::thread _usbThread;
    NSTextField* _throughputLabel;
    NSTextField* _dataLabel;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    [self setBackgroundColor:[[NSColor colorWithSRGBRed:((float)0x15/0xff) green:((float)0x15/0xff) blue:((float)0x15/0xff) alpha:1] CGColor]];
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        [self _pointAdd];
//    }];
    
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
        abort();
    }
    
    if (devices.empty()) {
        fprintf(stderr, "No matching MDC devices\n\n");
        abort();
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching MDC devices\n\n");
        abort();
    }
    
    MDCUSBDevice& device = *(devices[0]);
    
    
    
    static_assert(!(SD::BlockLen % Toastbox::USB::Endpoint::MaxPacketSizeBulk));
    const size_t len = (size_t)10000 * (size_t)SD::BlockLen;
    
    printf("Sending SDInit command...\n");
    device.sdInit();
    printf("-> OK\n\n");
    
    printf("Sending SDRead command...\n");
    device.sdRead((SD::Block)0x220200205);
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
        
        const uint32_t data = *((uint32_t*)buf.get());
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
            [self _pointAdd:throughputMBPerSec data:data];
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

- (void)_pointAdd:(float)throughput data:(uint32_t)data {
    CALayer* point = [CALayer new];
//    [point setBackgroundColor:[[NSColor lightGrayColor] CGColor]];
    [point setBackgroundColor:[[NSColor colorWithSRGBRed:((float)0x76/0xff) green:((float)0x46/0xff) blue:((float)0xff/0xff) alpha:1] CGColor]];
    
    const CGFloat boundsWidth = [self bounds].size.width;
    
    const CGFloat size = 5;
    [point setFrame:{0,0,size,size}];
    [point setCornerRadius:size/2];
//    [point setPosition:{boundsWidth,50}];
    [self addSublayer:point];
    
    CGFloat y = throughput*35-1205;
    CABasicAnimation* anim = [CABasicAnimation animationWithKeyPath:@"position"];
    [anim setFromValue:[NSValue valueWithPoint:{boundsWidth, y}]];
    [anim setToValue:[NSValue valueWithPoint:{0, y}]];
    [anim setDuration:10];
    [point addAnimation:anim forKey:@"position"];
    
//    [[_label layer] setActions:Toastbox::LayerNullActions];
    [_throughputLabel setStringValue:[NSString stringWithFormat:@"%.1f", throughput]];
    [_dataLabel setStringValue:[NSString stringWithFormat:@"0x%08jx", (uintmax_t)data]];
    
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
    IBOutlet NSTextField* _throughputLabel;
    IBOutlet NSTextField* _dataLabel;
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    PlotLayer* layer = [PlotLayer new];
    layer->_throughputLabel = _throughputLabel;
    layer->_dataLabel = _dataLabel;
    [_mainView setLayer:layer];
}

@end

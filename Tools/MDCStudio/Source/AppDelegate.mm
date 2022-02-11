#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <IOSurface/IOSurface.h>
#import <IOSurface/IOSurfaceObjC.h>
#import <vector>
#import <filesystem>
#import "Grid.h"
#import "ImageLibrary.h"
#import "MDCDevicesManager.h"
#import "ImageGrid/ImageGridView.h"
#import "MainView.h"
namespace fs = std::filesystem;

static std::vector<id> _Images;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@interface AppDelegate ()
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MainView* _mainView;
}

- (void)awakeFromNib {
//    __weak auto weakSelf = self;
//    MDCDevicesManager::AddObserver([=] {
//        [weakSelf _handleDevicesChanged];
//    });
    
    MDCDevicesManager::Start();
    
    ImageGridView* imageGridView = [[ImageGridView alloc] initWithFrame:{}];
    [_mainView setContentView:imageGridView];
}

- (void)_handleDevicesChanged {
//    printf("_handleDevicesChanged\n");
//    std::vector<MDCDevicePtr> devices = MDCDevicesManager::Devices();
//    bool first = true;
//    for (MDCDevicePtr dev : devices) {
//        dev->updateImageLibrary();
//        
//        if (first) {
//            [_imageGridView setImageLibrary:dev->imgLib()];
//        }
//        
//        first = false;
//    }
}

@end

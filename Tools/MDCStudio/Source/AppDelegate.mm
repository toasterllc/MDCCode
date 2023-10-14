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
#import "ImageGridView/ImageGridView.h"
using namespace MDCStudio;
namespace fs = std::filesystem;

static std::vector<id> _Images;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate
@end

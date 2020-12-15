#import "MainView.h"
#import <memory>
#import <iostream>
#import <regex>
#import <vector>
#import "ImageLayer.h"
#import "Mmap.h"
using namespace ImageLayerTypes;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MainView* _mainView;
    IBOutlet NSTextField* _colorMatrixTextField;
}

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    Mmap imageData("/Users/dave/repos/ImageProcessing/PureColor.cfa");
    constexpr size_t ImageWidth = 2304;
    constexpr size_t ImageHeight = 1296;
    Image image = {
        .width = ImageWidth,
        .height = ImageHeight,
        .pixels = (ImagePixel*)imageData.data(),
    };
    [[_mainView layer] updateImage:image];
}

- (IBAction)updateColorMatrix:(id)sender {
    const std::string str([[_colorMatrixTextField stringValue] UTF8String]);
    const std::regex floatRegex("[-+]?[0-9]*\\.?[0-9]+");
    auto begin = std::sregex_iterator(str.begin(), str.end(), floatRegex);
    auto end = std::sregex_iterator();
    std::vector<float> floats;
    
    for (std::sregex_iterator i=begin; i!=end; i++) {
        floats.push_back(std::stod(i->str()));
    }
    
    if (floats.size() != 9) {
        NSLog(@"Failed to parse color matrix");
        return;
    }
    
    const ColorMatrix cm{
        {floats[0], floats[3], floats[6]},  // Column 0
        {floats[1], floats[4], floats[7]},  // Column 1
        {floats[2], floats[5], floats[8]}   // Column 2
    };
    [[_mainView layer] updateColorMatrix:cm];
    
    
    
//    NSLog(@"updateColorMatrix: %@", str);
}

@end

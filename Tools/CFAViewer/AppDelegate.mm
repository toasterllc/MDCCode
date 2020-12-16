#import "MetalView.h"
#import <memory>
#import <iostream>
#import <regex>
#import <vector>
#import "ImageLayer.h"
#import "HistogramLayer.h"
#import "Mmap.h"
using namespace MetalTypes;
using namespace ImageLayerTypes;

@interface MainView : MetalView
@end

@implementation MainView
+ (Class)layerClass         { return [ImageLayer class];    }
- (ImageLayer*)imageLayer   { return (id)[self layer];      }
@end

@interface HistogramView : MetalView
@end

@implementation HistogramView
+ (Class)layerClass                 { return [HistogramLayer class];    }
- (HistogramLayer*)histogramLayer   { return (id)[self layer];          }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MainView* _mainView;
    IBOutlet HistogramView* _inputHistogramView;
    IBOutlet HistogramView* _outputHistogramView;
    
    IBOutlet NSTextField* _colorMatrixTextField;
}

- (void)awakeFromNib {
    Mmap imageData("/Users/dave/repos/ImageProcessing/PureColor.cfa");
    constexpr size_t ImageWidth = 2304;
    constexpr size_t ImageHeight = 1296;
    Image image = {
        .width = ImageWidth,
        .height = ImageHeight,
        .pixels = (MetalTypes::ImagePixel*)imageData.data(),
    };
    [[_mainView imageLayer] updateImage:image];
    
    __weak auto weakSelf = self;
    [[_mainView imageLayer] setHistogramChangedHandler:^(ImageLayer*) {
        [weakSelf _updateHistograms];
    }];
}

- (void)controlTextDidChange:(NSNotification*)note {
    if ([note object] == _colorMatrixTextField) {
        [self _updateColorMatrix];
    }
}

- (void)_updateColorMatrix {
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
    [[_mainView imageLayer] updateColorMatrix:cm];
}

- (void)_updateHistograms {
    [[_inputHistogramView histogramLayer] updateHistogram:[[_mainView imageLayer] inputHistogram]];
    [[_outputHistogramView histogramLayer] updateHistogram:[[_mainView imageLayer] outputHistogram]];
    
//    auto hist = [[_mainView imageLayer] outputHistogram];
//    size_t i = 0;
//    for (uint32_t& val : hist.r) {
//        if (!val) continue;
//        printf("[%ju]: %ju\n", (uintmax_t)i, (uintmax_t)val);
//        i++;
//    }
}

@end

#import <Cocoa/Cocoa.h>
#import "ImageSource.h"
#import "ImageSelection.h"
#import "Code/Shared/Img.h"

@interface InspectorView : NSView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource
    selection:(MDCStudio::ImageSelectionPtr)selection;
@end

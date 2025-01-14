#import <Cocoa/Cocoa.h>
#import "Shared/ImageSource.h"
#import "Shared/Img.h"
#import "ImageSelection.h"

@interface InspectorView : NSView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource
    selection:(MDCStudio::ImageSelectionPtr)selection;
@end

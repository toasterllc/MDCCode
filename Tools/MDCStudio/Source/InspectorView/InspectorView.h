#import <Cocoa/Cocoa.h>
#import "ImageSource.h"
#import "Code/Shared/Img.h"

@interface InspectorView : NSView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;
- (void)setSelection:(MDCStudio::ImageSet)selection;
@end

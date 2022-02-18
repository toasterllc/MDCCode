#import <Cocoa/Cocoa.h>
#import "ImageLibrary.h"

@interface ImageGridView : NSView

- (instancetype)initWithImageLibrary:(MDCStudio::ImageLibraryPtr)imgLib;

// -setResizingUnderway: is necessary to prevent artifacts when resizing
- (void)setResizingUnderway:(bool)resizing;
@end

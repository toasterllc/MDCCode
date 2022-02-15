#import <Cocoa/Cocoa.h>
#import "ImageLibrary.h"

@interface ImageGridView : NSView

- (instancetype)initWithImageLibrary:(ImageLibraryPtr)imgLib;

// -setResizingUnderway: is necessary to prevent artifacts when resizing
- (void)setResizingUnderway:(bool)resizing;
@end

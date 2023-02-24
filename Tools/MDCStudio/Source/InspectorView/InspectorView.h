#import <Cocoa/Cocoa.h>
#import "ImageLibrary.h"
#import "Code/Shared/Img.h"

@interface InspectorView : NSView
- (instancetype)initWithImageLibrary:(MDCStudio::ImageLibraryPtr)imgLib;
- (void)setSelection:(const std::set<Img::Id>&)selection;
@end

#import <Cocoa/Cocoa.h>
#import "ImageLibrary.h"
#import "Code/Shared/Img.h"

@interface InspectorView : NSView
- (instancetype)initWithImageLibrary:(MDCStudio::ImageLibraryPtr)imgLib;
- (void)setSelection:(std::set<MDCStudio::ImageRecordPtr>)selection;
@end

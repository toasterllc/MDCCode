#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageSelection.h"
@class ImageGridView;
@class ImageGridScrollView;

@interface ImageGridContainerView : NSView
- (instancetype)initWithImageGridView:(ImageGridView*)imageGridView;
- (ImageGridView*)imageGridView;
- (ImageGridScrollView*)imageGridScrollView;
@end

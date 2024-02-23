#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageSelection.h"
#import "ContentViewable.h"
@class ImageGridView;
@class ImageGridScrollView;

@interface ImageGridContainerView : NSView <ContentViewable>
- (instancetype)initWithImageGridView:(ImageGridView*)imageGridView;
- (ImageGridView*)imageGridView;
- (ImageGridScrollView*)imageGridScrollView;
@end

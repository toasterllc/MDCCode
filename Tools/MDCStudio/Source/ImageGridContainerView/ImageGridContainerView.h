#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageSelection.h"
#import "CenterContent.h"
@class ImageGridView;
@class ImageGridScrollView;

@interface ImageGridContainerView : NSView <CenterContent>
- (instancetype)initWithImageGridView:(ImageGridView*)imageGridView;
- (ImageGridView*)imageGridView;
- (ImageGridScrollView*)imageGridScrollView;
@end

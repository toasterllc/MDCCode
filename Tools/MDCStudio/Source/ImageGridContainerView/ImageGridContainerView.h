#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageSelection.h"
#import "CenterContentView.h"
@class ImageGridView;
@class ImageGridScrollView;

@interface ImageGridContainerView : NSView <CenterContentView>
- (instancetype)initWithImageGridView:(ImageGridView*)imageGridView;
- (ImageGridView*)imageGridView;
- (ImageGridScrollView*)imageGridScrollView;
@end

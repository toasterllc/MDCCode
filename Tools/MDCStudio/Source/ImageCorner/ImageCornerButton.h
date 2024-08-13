#import <Cocoa/Cocoa.h>
#import "ImageCorner.h"

@interface ImageCornerButton : NSButton

- (MDCStudio::ImageCorner)corner;
- (void)setCorner:(MDCStudio::ImageCorner)corner;

@end

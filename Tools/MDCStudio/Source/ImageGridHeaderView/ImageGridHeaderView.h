#import <Cocoa/Cocoa.h>
@class ImageGridHeaderView;

@protocol ImageGridHeaderViewDelegate
@required
- (void)imageGridHeaderViewLoad:(ImageGridHeaderView*)x;
@end

@interface ImageGridHeaderView : NSView
- (void)setDelegate:(id<ImageGridHeaderViewDelegate>)x;
- (void)setLoadCount:(NSUInteger)x;
- (CGFloat)height;

- (void)setStatus:(NSString*)status;

@end

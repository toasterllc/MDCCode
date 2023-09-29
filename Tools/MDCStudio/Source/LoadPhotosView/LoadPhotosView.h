#import <Cocoa/Cocoa.h>
@class LoadPhotosView;

@protocol LoadPhotosViewDelegate
@required
- (void)loadPhotosViewLoad:(LoadPhotosView*)x;
@end

@interface LoadPhotosView : NSView
- (void)setDelegate:(id<LoadPhotosViewDelegate>)x;
- (void)setLoadCount:(NSUInteger)x;
- (CGFloat)height;
@end

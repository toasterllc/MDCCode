#import <Cocoa/Cocoa.h>
#import "ImageSource.h"
#import "FixedDocumentView.h"
@class FullSizeImageContainerView;

@protocol FullSizeImageViewDelegate
@required
- (void)fullSizeImageViewPreviousImage:(FullSizeImageContainerView*)imageView;
- (void)fullSizeImageViewNextImage:(FullSizeImageContainerView*)imageView;
@end

@interface FullSizeImageContainerView : NSView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;
- (MDCStudio::ImageRecordPtr)imageRecord;
- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec;
- (void)setDelegate:(id<FullSizeImageViewDelegate>)delegate;
@end

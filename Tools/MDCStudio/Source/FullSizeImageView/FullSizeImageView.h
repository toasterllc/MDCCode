#import <Cocoa/Cocoa.h>
#import "ImageSource.h"
#import "FixedDocumentView.h"
@class FullSizeImageView;

@protocol FullSizeImageViewDelegate
@required
- (void)fullSizeImageViewBack:(FullSizeImageView*)imageView;
- (void)fullSizeImageViewPreviousImage:(FullSizeImageView*)imageView;
- (void)fullSizeImageViewNextImage:(FullSizeImageView*)imageView;
@end

@interface FullSizeImageView : NSView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;
- (MDCStudio::ImageRecordPtr)imageRecord;
- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec;
- (void)setDelegate:(id<FullSizeImageViewDelegate>)delegate;
- (void)magnifyToFit;
@end

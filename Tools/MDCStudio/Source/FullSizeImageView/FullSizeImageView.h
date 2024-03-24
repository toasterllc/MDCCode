#import <Cocoa/Cocoa.h>
#import "ImageSource.h"
#import "AnchoredDocumentView.h"
#import "CenterContent.h"
@class FullSizeImageView;

@protocol FullSizeImageViewResponder
@optional
- (void)_backToImages:(id)sender;
@end

@interface FullSizeImageView : NSView <CenterContent>
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;
- (MDCStudio::ImageRecordPtr)imageRecord;
- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec;
- (void)magnifyToFit;
@end

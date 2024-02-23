#import <Cocoa/Cocoa.h>
#import "ImageSource.h"
#import "FixedDocumentView.h"
#import "CenterContentView.h"
@class FullSizeImageView;

@protocol FullSizeImageViewResponder
@optional
- (void)_backToImages:(id)sender;
@end

@interface FullSizeImageView : NSView <CenterContentView>
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;
- (MDCStudio::ImageRecordPtr)imageRecord;
- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec;
- (void)magnifyToFit;
@end

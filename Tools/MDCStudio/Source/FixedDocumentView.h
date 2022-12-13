#import <Cocoa/Cocoa.h>
#import "FixedScrollView.h"

@interface FixedDocumentView : NSView <FixedScrollViewDocument>
- (void)setFixedLayer:(CALayer<FixedScrollViewDocument>*)layer;
@end

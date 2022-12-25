#import <Cocoa/Cocoa.h>
#import "FixedScrollView.h"

// FixedDocumentView: a document view (to be used with FixedScrollView) that merely hosts a layer.
// FixedDocumentView forwards the FixedScrollViewDocument protocol methods to its layer.
@interface FixedDocumentView : NSView <FixedScrollViewDocument>
- (instancetype)initWithFixedLayer:(CALayer<FixedScrollViewDocument>*)layer;
//- (CGPoint)convertPointToFixedDocument:(CGPoint)point fromView:(NSView*)view;
//- (CGRect)convertRectToFixedDocument:(CGRect)rect fromView:(NSView*)view;
@end

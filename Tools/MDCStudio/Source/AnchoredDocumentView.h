#import <Cocoa/Cocoa.h>
#import "AnchoredScrollView.h"

// AnchoredDocumentView: a document view (to be used with AnchoredScrollView) that merely hosts a layer.
// AnchoredDocumentView forwards the AnchoredScrollViewDocument protocol methods to its layer.
@interface AnchoredDocumentView : NSView <AnchoredScrollViewDocument>
- (instancetype)initWithAnchoredLayer:(CALayer<AnchoredScrollViewDocument>*)layer;
@end

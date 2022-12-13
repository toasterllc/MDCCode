#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import "FixedScrollView.h"

@interface FixedMetalDocumentLayer : CAMetalLayer <FixedScrollViewDocument>
// To implement drawing, subclasses should override -display. Subclasses
// must call super's implementation to set up the Metal drawable.
- (void)display;

// -fixedDocumentSize: the total size of the scrollable/zoomable document.
// (Ie, the size of the 'universe'.)
- (CGSize)fixedDocumentSize;

// -fixedTransform: returns the matrix that incorporates the current magnification and translation.
// The matrix converts normalized [0,1] coordinates within the receiver's full-size content
// to normalized device coordinates (NDC) in the range [-1,1] where this NDC range x,y=[-1,1]
// represents the visible region of the receiver, after magnification and translation.
- (simd_float4x4)fixedTransform;

@end

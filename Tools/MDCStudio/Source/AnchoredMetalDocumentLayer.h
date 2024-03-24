#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import "AnchoredScrollView.h"

@interface AnchoredMetalDocumentLayer : CAMetalLayer <AnchoredScrollViewDocument>
// To implement drawing, subclasses should override -display. Subclasses
// must call super's implementation to set up the Metal drawable.
- (void)display;

- (CGPoint)anchoredTranslation;
- (CGFloat)anchoredMagnification;

// -anchoredTransform: returns the matrix that incorporates the current magnification and translation.
// The matrix converts normalized [0,1] coordinates within the receiver's full-size content to
// normalized device coordinates (NDC), where the NDC range [-1,1] represents the visible region of
// the receiver, after magnification and translation.
- (simd_float4x4)anchoredTransform;

@end

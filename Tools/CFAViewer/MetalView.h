#import <Cocoa/Cocoa.h>

@interface MetalView : NSView
// Subclass must override
+ (Class)layerClass;

// Subclass can override, and must call super
- (void)commonInit;

@end

#import <Cocoa/Cocoa.h>

@interface MetalView : NSView
+ (Class)layerClass; // Subclass must override
@end

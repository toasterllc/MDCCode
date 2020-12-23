#import <Cocoa/Cocoa.h>

@interface BaseView : NSView

// Subclass can override if it wants a custom layer class
+ (Class)layerClass;

// Subclass can override, and must call super
- (void)commonInit;

@end

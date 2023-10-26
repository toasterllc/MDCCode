#import <Cocoa/Cocoa.h>

using FactoryResetConfirmationAlertHandler = void(^)(NSModalResponse);

@interface FactoryResetConfirmationAlert : NSAlert

- (void)beginSheetModalForWindow:(NSWindow*)window
    completionHandler:(FactoryResetConfirmationAlertHandler)handler;

- (void)setSpinnerVisible:(bool)x;

- (void)dismiss;

@end

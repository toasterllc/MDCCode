#import "DocumentController.h"

@implementation DocumentController

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
//    NSLog(@"[DocumentController] validateMenuItem: %@\n", [item title]);
    if ([item action] == @selector(openDocument:)) {
        return false;
    }
    return true;
}

@end

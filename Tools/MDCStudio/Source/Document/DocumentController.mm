#import "DocumentController.h"

@implementation DocumentController

- (BOOL)validateMenuItem:(NSMenuItem*)item {
//    NSLog(@"[DocumentController] validateMenuItem: %@\n", [item title]);
    if ([item action] == @selector(openDocument:)) {
        return false;
    }
    return true;
}

@end

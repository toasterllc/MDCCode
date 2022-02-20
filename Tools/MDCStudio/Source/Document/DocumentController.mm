#import "DocumentController.h"

@implementation DocumentController

- (BOOL)validateMenuItem:(NSMenuItem*)item {
    if ([item action] == @selector(openDocument:)) {
        return false;
    }
    return true;
}

@end

#import <Cocoa/Cocoa.h>

namespace CenterContentTypes {
    // The NSNotification posted when the value of -sourceListAllowed/-inspectorAllowed changed
    constexpr const char* ChangedNotification = "CenterContentTypes::ChangedNotification";
};

// CenterContent: protocol for a content view
@protocol CenterContent
@optional
- (NSView*)initialFirstResponder;
- (bool)sourceListAllowed;
- (bool)inspectorAllowed;
@end

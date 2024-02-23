#import <Cocoa/Cocoa.h>

namespace ContentViewableTypes {
    // The NSNotification posted when the value of -sourceListAllowed/-inspectorAllowed changed
    constexpr const char* ChangedNotification = "ContentViewableTypes::ChangedNotification";
};

// ContentViewable: protocol for a content view
@protocol ContentViewable
@optional
- (NSView*)initialFirstResponder;
- (bool)sourceListAllowed;
- (bool)inspectorAllowed;
@end

#import <Cocoa/Cocoa.h>

namespace CenterContentViewTypes {
    // The NSNotification posted when the value of -sourceListAllowed/-inspectorAllowed changed
    constexpr const char* ChangedNotification = "CenterContentViewTypes::ChangedNotification";
};

// CenterContentView: protocol for a content view
@protocol CenterContentView
@optional
- (NSView*)initialFirstResponder;
- (bool)sourceListAllowed;
- (bool)inspectorAllowed;
@end

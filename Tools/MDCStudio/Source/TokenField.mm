#import "TokenField.h"
#import "Toastbox/Mac/Util.h"

@implementation TokenField {
    bool _init;
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self invalidateIntrinsicContentSize];
}

- (NSSize)intrinsicContentSize {
    constexpr CGFloat Inset = 4; // Empirically determined
    CGSize s = [self sizeThatFits:{[self frame].size.width-Inset, CGFLOAT_MAX}];
    s.width = NSViewNoIntrinsicMetric;
    return s;
}

- (void)textDidChange:(NSNotification*)note {
    [super textDidChange:note];
    [self invalidateIntrinsicContentSize];
}

// Fix default NSTokenField behavior, which doesn't trigger the delegate validation
// callback (-tokenField:shouldAddObjects:atIndex:) when finishing editing in some
// cases (eg when when using the tab key or clicking on another field).
- (BOOL)textShouldEndEditing:(NSText*)text {
    if (auto client = CastProtocol(NSTextInputClient, text)) {
        NSString*const Delimeter = @"\0";
        if (!_init) {
            _init = true;
            NSMutableCharacterSet* s = [[self tokenizingCharacterSet] mutableCopy];
            [s addCharactersInString:Delimeter];
            [self setTokenizingCharacterSet:s];
        }
        // We need to use -insertText:replacementRange: on NSTextInputClient,
        // and not -insertText: on NSTextView, because -insertText: will
        // overwrite selected text.
        const NSRange range = [client selectedRange];
        [client insertText:Delimeter replacementRange:{range.location+range.length, 0}];
    }
    
    return [super textShouldEndEditing:text];
}

- (void)textDidEndEditing:(NSNotification*)note {
    NSLog(@"%@", NSStringFromSelector(_cmd));
    [super textDidEndEditing:note];
}

@end

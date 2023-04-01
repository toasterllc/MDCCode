#import "TokenField.h"

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
// callback (-tokenField:shouldAddObjects:atIndex:) when using the tab key to finish
// editing the field
- (BOOL)textShouldEndEditing:(NSText*)text {
    NSString*const Delimeter = @"\0";
    if (!_init) {
        _init = true;
        NSMutableCharacterSet* s = [[self tokenizingCharacterSet] mutableCopy];
        [s addCharactersInString:Delimeter];
        [self setTokenizingCharacterSet:s];
    }
    [text insertText:Delimeter];
    return [super textShouldEndEditing:text];
}

@end

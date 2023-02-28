#import "ImageCornerButton.h"
using namespace ImageCornerButtonTypes;

@implementation ImageCornerButton {
    Corner _corner;
}

static void _Init(ImageCornerButton* self) {
    [self setCorner:Corner::BottomRight];
}

static Corner _CornerNext(Corner x, int delta) {
    if ((x==Corner::TopRight && delta>0) || x==Corner::Mixed) return Corner::BottomRight;
    if (x==Corner::BottomRight && delta<0) return Corner::TopRight;
    return (Corner)((int)x+delta);
}

//static Corner _CornerNext(Corner x, int delta) {
//    if (delta > 0) {
//        switch (x) {
//        case Corner::BottomRight:   return Corner::BottomLeft;
//        case Corner::BottomLeft:    return Corner::TopLeft;
//        case Corner::TopLeft:       return Corner::TopRight;
//        case Corner::TopRight:      return Corner::BottomRight;
//        case Corner::Mixed:         return Corner::BottomRight;
//        }
//    } else {
//        switch (x) {
//        case Corner::BottomRight:   return Corner::TopRight;
//        case Corner::BottomLeft:    return Corner::BottomRight;
//        case Corner::TopLeft:       return Corner::BottomLeft;
//        case Corner::TopRight:      return Corner::TopLeft;
//        case Corner::Mixed:         return Corner::BottomRight;
//        }
//    }
//}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _Init(self);
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _Init(self);    
    return self;
}

- (BOOL)sendAction:(SEL)action to:(id)target {
    NSEvent*const ev = [NSApp currentEvent];
    const int delta = (([ev modifierFlags] & NSEventModifierFlagShift) ? -1 : 1);
    [self setCorner:_CornerNext(_corner, delta)];
    return [super sendAction:action to:target];
}

- (ImageCornerButtonTypes::Corner)corner {
    return _corner;
}

- (void)setCorner:(ImageCornerButtonTypes::Corner)corner {
    _corner = corner;
    [self setImage:[NSImage imageNamed:[NSString stringWithFormat:@"ImageCornerButton-%d", (int)corner]]];
}

@end

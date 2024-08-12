#import "ImageCornerButton.h"
using namespace MDCStudio;

@implementation ImageCornerButton {
    ImageCorner _corner;
}

static void _Init(ImageCornerButton* self) {
    [self setCorner:ImageCorner::BottomRight];
}

//static Corner _CornerNext(Corner x, int delta) {
//    if ((x==Corner::TopRight && delta>0) || x==Corner::Mixed) return Corner::BottomRight;
//    if (x==Corner::BottomRight && delta<0) return Corner::TopRight;
//    return (Corner)((int)x+delta);
//}

static ImageCorner _CornerNext(ImageCorner x, int delta) {
    if (delta >= 0) {
        switch (x) {
        case ImageCorner::BottomRight:   return ImageCorner::BottomLeft;
        case ImageCorner::BottomLeft:    return ImageCorner::TopLeft;
        case ImageCorner::TopLeft:       return ImageCorner::TopRight;
        case ImageCorner::TopRight:      return ImageCorner::BottomRight;
        }
    } else {
        switch (x) {
        case ImageCorner::BottomRight:   return ImageCorner::TopRight;
        case ImageCorner::BottomLeft:    return ImageCorner::BottomRight;
        case ImageCorner::TopLeft:       return ImageCorner::BottomLeft;
        case ImageCorner::TopRight:      return ImageCorner::TopLeft;
        }
    }
    abort();
}

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

- (MDCStudio::ImageCorner)corner {
    return _corner;
}

- (void)setCorner:(MDCStudio::ImageCorner)corner {
    _corner = corner;
    [self setImage:[NSImage imageNamed:[NSString stringWithFormat:@"ImageCornerButton-%d", (int)corner]]];
}

@end

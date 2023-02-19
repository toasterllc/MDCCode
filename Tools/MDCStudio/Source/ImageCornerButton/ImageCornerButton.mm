#import "ImageCornerButton.h"
using namespace ImageCornerButtonTypes;

@implementation ImageCornerButton {
    Corner _corner;
}

static void _Init(ImageCornerButton* self) {
    [self setCorner:Corner::BottomLeft];
}

static Corner _CornerNext(Corner x) {
    if (x == Corner::TopLeft) return Corner::BottomLeft;
    return (Corner)((int)x+1);
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
    [self setCorner:_CornerNext(_corner)];
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

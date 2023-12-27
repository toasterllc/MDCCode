#import "ProgressBar.h"

@implementation ProgressBar {
    CALayer* _bar;
    float _progress;
}

static void _Init(ProgressBar* self) {
    CALayer* layer = [CALayer new];
    CALayer* bar = [CALayer new];
    [layer setBackgroundColor:[[NSColor colorWithSRGBRed:0.310 green:0.310 blue:0.310 alpha:1] CGColor]];
    [bar setBackgroundColor:[[NSColor colorWithSRGBRed:0.090 green:0.412 blue:0.902 alpha:1] CGColor]];
    [layer addSublayer:bar];
    self->_bar = bar;
    [self setLayer:layer];
    [self setWantsLayer:true];
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

- (void)setProgress:(float)x {
    _progress = x;
    [self setNeedsLayout:true];
}

- (void)layout {
    [super layout];
    CGRect f = [self frame];
    [_bar setFrame:{0,0,f.size.width*_progress, f.size.height}];
}

@end

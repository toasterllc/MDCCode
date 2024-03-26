#import "ProgressBar.h"
#import "Code/Lib/Toastbox/Mac/Util.h"

@implementation ProgressBar {
    CALayer* _bar;
    float _progress;
}

static void _Init(ProgressBar* self) {
    CALayer* bar = [CALayer new];
    [bar setBackgroundColor:[[NSColor colorWithSRGBRed:0.090 green:0.412 blue:0.902 alpha:1] CGColor]];
    [bar setActions:Toastbox::LayerNullActions];
    
    CALayer* layer = [CALayer new];
    [layer setBackgroundColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:.075] CGColor]];
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

#import "ColorButtonCell.h"

inline NSDictionary* LayerNullActions = @{
    kCAOnOrderIn: [NSNull null],
    kCAOnOrderOut: [NSNull null],
    @"bounds": [NSNull null],
    @"frame": [NSNull null],
    @"position": [NSNull null],
    @"sublayers": [NSNull null],
    @"transform": [NSNull null],
    @"contents": [NSNull null],
    @"contentsScale": [NSNull null],
    @"hidden": [NSNull null],
    @"fillColor": [NSNull null],
    @"fontSize": [NSNull null],
};

@implementation ColorButtonCell {
    NSColor* _color;
    NSColor* _highlightColor;
    CALayer* _layer;
}

static void _Init(ColorButtonCell* self) {
    NSButton* button = (id)[self controlView];
    [button setWantsLayer:true];
    [button setBordered:false];
    
    CALayer* layer = [button layer];
    [layer setActions:LayerNullActions];
    [layer setCornerRadius:5];
    [layer setBackgroundColor:[[NSColor whiteColor] CGColor]];
    [layer setShadowColor:[[NSColor blackColor] CGColor]];
    [layer setShadowOffset:{0,.5}];
    [layer setShadowRadius:.5];
    [layer setShadowOpacity:1];
    [layer setMasksToBounds:false];
    self->_layer = layer;
}

- (instancetype)initTextCell:(NSString*)string {
    if (!(self = [super initTextCell:string])) return nil;
    _Init(self);
    return self;
}

- (instancetype)initImageCell:(NSImage*)image {
    if (!(self = [super initImageCell:image])) return nil;
    _Init(self);
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _Init(self);
    return self;
}

- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView*)controlView {}
- (void)drawImage:(NSImage*)image withFrame:(NSRect)frame inView:(NSView*)controlView {}
- (NSRect)drawTitle:(NSAttributedString*)title withFrame:(NSRect)frame inView:(NSView*)controlView { return {}; }

- (void)highlight:(BOOL)highlight withFrame:(NSRect)cellFrame inView:(NSView*)controlView {
    [_layer setBackgroundColor:[(highlight ? _highlightColor : _color) CGColor]];
}

- (NSRect)imageRectForBounds:(NSRect)rect {
    return rect;
}

- (NSRect)titleRectForBounds:(NSRect)rect {
    return rect;
}

- (NSRect)drawingRectForBounds:(NSRect)rect {
    return rect;
}

- (NSSize)cellSizeForBounds:(NSRect)rect {
    return rect.size;
}

static NSColor* _HighlightColorForColor(NSColor* c) {
    constexpr CGFloat Factor = 0.65;
    auto h = [c hueComponent];
    auto s = [c saturationComponent];
    auto v = [c brightnessComponent];
    return [NSColor colorWithColorSpace:[c colorSpace] hue:h saturation:s brightness:Factor*v alpha:1];
}

- (void)setColor:(NSColor*)color {
    _color = color;
    _highlightColor = _HighlightColorForColor(_color);
    [_layer setBackgroundColor:[_color CGColor]];
}

@end

#import "BaseView.h"
#import <memory>

@implementation BaseView {
    CALayer* _layer;
}

+ (Class)layerClass {
    return [CALayer class];
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self commonInit];
    return self;
}

- (void)commonInit {
    _layer = [[[self class] layerClass] new];
    [self setLayer:_layer];
    [self setWantsLayer:true];
}

static void setContentsScaleForSublayers(CALayer* layer, CGFloat contentsScale) {
    [layer setContentsScale:contentsScale];
    for (CALayer* sublayer : [layer sublayers]) {
        setContentsScaleForSublayers(sublayer, contentsScale);
    }
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    const CGFloat contentsScale = [[self window] backingScaleFactor];
    setContentsScaleForSublayers(_layer, contentsScale);
}

@end

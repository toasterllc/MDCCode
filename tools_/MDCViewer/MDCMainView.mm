#import "MDCMainView.h"
#import "MDCImageLayer.h"
#import <memory>
using namespace MDCImageLayerTypes;

@implementation MDCMainView {
    MDCImageLayer* _layer;
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
    _layer = [MDCImageLayer new];
    [self setLayer:_layer];
    [self setWantsLayer:true];
}

#pragma mark - Contents Scale

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

- (MDCImageLayer*)layer {
    return _layer;
}

@end

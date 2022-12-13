#import "FixedDocumentView.h"
#import <algorithm>

@implementation FixedDocumentView {
    CALayer<FixedScrollViewDocument>* _layer;
}

- (void)setFixedLayer:(CALayer<FixedScrollViewDocument>*)layer {
    assert(!_layer);
    _layer = layer;
    [self setLayer:_layer];
    [self setWantsLayer:true];
    
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
    [_layer setGeometryFlipped:[self isFlipped]];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
}

- (void)setTranslation:(CGPoint)t magnification:(CGFloat)m {
    [_layer setTranslation:t magnification:m];
}

@end

#import "AnchoredDocumentView.h"
#import <algorithm>

@implementation AnchoredDocumentView {
    CALayer<AnchoredScrollViewDocument>* _layer;
}

- (instancetype)initWithAnchoredLayer:(CALayer<AnchoredScrollViewDocument>*)layer {
    NSParameterAssert(layer);
    if (!(self = [super initWithFrame:{}])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _layer = layer;
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
    [self setLayer:_layer];
    [self setWantsLayer:true];
    return self;
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
}

- (void)anchoredTranslationChanged:(CGPoint)t magnification:(CGFloat)m {
    [_layer anchoredTranslationChanged:t magnification:m];
}

- (void)anchoredCreateConstraintsForContainer:(NSView*)container {
    if ([_layer respondsToSelector:@selector(anchoredCreateConstraintsForContainer:)]) {
        [_layer anchoredCreateConstraintsForContainer:container];
    
    } else {
        const CGSize size = [_layer preferredFrameSize];
        NSLayoutConstraint* width = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
            constant:size.width];
        [width setActive:true];
        
        NSLayoutConstraint* height = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
            constant:size.height];
        [height setActive:true];
    }
}

- (bool)anchoredFlipped {
    return [_layer anchoredFlipped];
}

@end

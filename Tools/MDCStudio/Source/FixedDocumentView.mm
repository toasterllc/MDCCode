#import "FixedDocumentView.h"
#import <algorithm>

@implementation FixedDocumentView {
    CALayer<FixedScrollViewDocument>* _layer;
}

- (instancetype)initWithFixedLayer:(CALayer<FixedScrollViewDocument>*)layer {
    NSParameterAssert(layer);
    if (!(self = [super initWithFrame:{}])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _layer = layer;
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
//    [_layer setGeometryFlipped:[self isFlipped]];
    [self setLayer:_layer];
    [self setWantsLayer:true];
    return self;
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
}

//- (NSArray*)fixedConstraintsForContainer:(NSView*)container {
//    return [_layer fixedConstraintsForContainer:container];
//}

//- (CGSize)fixedContentSize {
//    return [_layer fixedContentSize];
//}

- (void)setFixedTranslation:(CGPoint)t magnification:(CGFloat)m {
    [_layer setFixedTranslation:t magnification:m];
}

- (void)createFixedConstraintsForContainer:(NSView*)container {
    if ([_layer respondsToSelector:@selector(createFixedConstraintsForContainer:)]) {
        [_layer createFixedConstraintsForContainer:container];
    
    } else {
        const CGSize size = [_layer preferredFrameSize];
        NSLayoutConstraint* width = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
            constant:size.width];
        
        NSLayoutConstraint* height = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
            constant:size.height];
        
        [NSLayoutConstraint activateConstraints:@[width, height]];
    }
}

- (bool)fixedFlipped {
    return [_layer fixedFlipped];
}

- (CGPoint)convertPointToFixedDocument:(CGPoint)point fromView:(NSView*)view {
    return [[self superview] convertPoint:point fromView:view];
}

- (CGRect)convertRectToFixedDocument:(CGRect)rect fromView:(NSView*)view {
    return [[self superview] convertRect:rect fromView:view];
}

@end

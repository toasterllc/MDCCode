#import "MainView.h"
#import <algorithm>
#import "SourceListView/SourceListView.h"
#import "Util.h"
#import "ImageGridView/ImageGridView.h"
#import "ImageView/ImageView.h"
using namespace MDCStudio;

namespace SourceListWidth {
    static constexpr CGFloat HideThreshold  = 50;
    static constexpr CGFloat Min            = 150;
    static constexpr CGFloat Default        = 220;
}

namespace ContentWidth {
    static constexpr CGFloat Min = 200;
}

#define ResizerView MainView_ResizerView

using ResizerViewHandler = void(^)(NSEvent* event);

@interface ResizerView : NSView
@end

@implementation ResizerView {
@public
    ResizerViewHandler handler;
    NSCursor* cursor;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    return self;
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [[self window] invalidateCursorRectsForView:self];
}

- (void)resetCursorRects {
    [self addCursorRect:[self bounds] cursor:cursor];
}

- (void)mouseDown:(NSEvent*)event {
    handler(event);
}

@end

@interface AnimationStoppedDelegate : NSObject <CAAnimationDelegate>
@end

@implementation AnimationStoppedDelegate {
@public
    void (^animationStoppedBlock)();
}
- (void)animationDidStop:(CAAnimation*)anim finished:(BOOL)flag {
    if (animationStoppedBlock) {
        animationStoppedBlock();
    }
}
@end


@interface MainView ()
@end

@implementation MainView {
    SourceListView* _sourceListView;
    NSLayoutConstraint* _sourceListWidth;
    NSLayoutConstraint* _sourceListMinWidth;
    bool _sourceListVisible;
    
    NSView* _contentContainerView;
    NSView* _contentView;
    
    ResizerView* _resizerView;
    bool _dragging;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self initCommon];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self initCommon];
    return self;
}

- (void)initCommon {
    // Configure `self`
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        [self setWantsLayer:true];
        [[self layer] setBackgroundColor:[[NSColor colorWithSRGBRed:WindowBackgroundColor.srgb[0]
            green:WindowBackgroundColor.srgb[1] blue:WindowBackgroundColor.srgb[2] alpha:1] CGColor]];
    }
    
    // Create source list
    {
        _sourceListView = [[SourceListView alloc] initWithFrame:{}];
        [self addSubview:_sourceListView];
        
        _sourceListWidth = [NSLayoutConstraint constraintWithItem:_sourceListView attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
            multiplier:0 constant:SourceListWidth::Default];
        [_sourceListWidth setPriority:NSLayoutPriorityDragThatCannotResizeWindow];
        [self addConstraint:_sourceListWidth];
        
        _sourceListMinWidth = [NSLayoutConstraint constraintWithItem:_sourceListView attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
            multiplier:0 constant:SourceListWidth::Min];
        [self addConstraint:_sourceListMinWidth];
    }
    
    // Create content container view
    {
        _contentContainerView = [[NSView alloc] initWithFrame:{}];
        [_contentContainerView setWantsLayer:true];
        
//        [_contentContainerView setWantsLayer:true];
//        [[_contentContainerView layer] setBackgroundColor:[[[NSColor redColor] colorWithAlphaComponent:.2] CGColor]];
        
        [_contentContainerView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:_contentContainerView];
        
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_sourceListView][_contentContainerView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_sourceListView, _contentContainerView)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_sourceListView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_sourceListView)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_contentContainerView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_contentContainerView)]];
        
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_contentContainerView attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
            multiplier:0 constant:ContentWidth::Min]];
        
    }
    
    // Resizer
    {
        constexpr CGFloat ResizerWidth = 20;
        __weak auto weakSelf = self;
        _resizerView = [[ResizerView alloc] initWithFrame:NSZeroRect];
        
//        [_resizerView setWantsLayer:true];
//        [[_resizerView layer] setBackgroundColor:[[[NSColor blueColor] colorWithAlphaComponent:.2] CGColor]];
        
        _resizerView->handler = ^(NSEvent* event) { [weakSelf _sourceListTrackResize:event]; };
        _resizerView->cursor = [NSCursor resizeLeftRightCursor];
        
        [self addSubview:_resizerView];
        [_resizerView addConstraint:[NSLayoutConstraint constraintWithItem:_resizerView attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:ResizerWidth]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_resizerView attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeHeight multiplier:1 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_resizerView attribute:NSLayoutAttributeCenterX
            relatedBy:NSLayoutRelationEqual toItem:_sourceListView attribute:NSLayoutAttributeRight
            multiplier:1 constant:0]];
    }
}

- (SourceListView*)sourceListView {
    return _sourceListView;
}

- (NSView*)contentView {
    return _contentView;
}

- (void)setContentView:(NSView*)contentView animation:(MainViewAnimation)animation {
    constexpr CFTimeInterval AnimationDuration = .2;
    const CAMediaTimingFunctionName AnimationTimingFunction = kCAMediaTimingFunctionEaseOut;
    NSString*const AnimationName = @"slide";
    const CGFloat slideWidth = [_contentContainerView bounds].size.width;
    
//    if (_contentView && animation!=MainViewAnimation::None) {
////        __weak NSView* contentViewWeak = _contentView;
////        
////        CABasicAnimation* anim = [[_contentView layer] animationForKey:AnimationName];
////        if (anim) {
////            [NSTimer scheduledTimerWithTimeInterval:1 repeats:false block:^(NSTimer* timer) {
////                [contentViewWeak removeFromSuperview];
////            }];
////        
////        } else {
////            AnimationStoppedDelegate* delegate = [AnimationStoppedDelegate new];
////            delegate->animationStoppedBlock = ^{
////                [contentViewWeak removeFromSuperview];
////            };
////            
////            const CGFloat posStart = [[[_contentView layer] presentationLayer] position].x;
////            const CGFloat posEnd = (animation==MainViewAnimation::SlideToLeft ? -slideWidth : slideWidth);
//////            const float progressRemaining = (std::abs(posStart-posEnd) / containerWidth);
////            
////            CABasicAnimation* slide = [CABasicAnimation animationWithKeyPath:@"position.x"];
////            [slide setTimingFunction:[CAMediaTimingFunction functionWithName:AnimationTimingFunction]];
////            [slide setDelegate:delegate];
////            [slide setFromValue:@(posStart)];
////            [slide setToValue:@(posEnd)];
////            [slide setDuration:AnimationDuration];
////            [[_contentView layer] addAnimation:slide forKey:AnimationName];
////            [[_contentView layer] setValue:@(posEnd) forKeyPath:@"position.x"];
////            
////            
//////            CABasicAnimation* fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
//////            [fade setTimingFunction:[CAMediaTimingFunction functionWithName:AnimationTimingFunction]];
//////            [fade setFromValue:@0];
//////            [fade setToValue:@1];
//////            [fade setDuration:AnimationDuration];
//////            [[_contentView layer] addAnimation:fade forKey:AnimationName];
//////            [[_contentView layer] setValue:@1 forKeyPath:@"opacity"];
////            
////        }
//    
//    } else {
//        [_contentView removeFromSuperview];
//    }
    
    NSView* oldContentView = _contentView;
    if (_contentView && animation==MainViewAnimation::None) {
        [_contentView removeFromSuperview];
    }
    
    _contentView = contentView;
    if (!_contentView) return;
    
    [_contentView setTranslatesAutoresizingMaskIntoConstraints:false];
    [_contentContainerView addSubview:contentView];
    [_contentContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_contentView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_contentView)]];
    [_contentContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_contentView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_contentView)]];
    
    if (_contentView) {
        [[self window] makeFirstResponder:_contentView];
    }
    
    if (_contentView && animation!=MainViewAnimation::None) {
        const CGFloat posStart = (animation==MainViewAnimation::SlideToLeft ? slideWidth : -slideWidth);
        const CGFloat posEnd = 0;
        
        AnimationStoppedDelegate* delegate = [AnimationStoppedDelegate new];
        delegate->animationStoppedBlock = ^{
            [oldContentView removeFromSuperview];
        };
        
        CABasicAnimation* slide = [CABasicAnimation animationWithKeyPath:@"position.x"];
        [slide setDelegate:delegate];
        [slide setTimingFunction:[CAMediaTimingFunction functionWithName:AnimationTimingFunction]];
        [slide setFromValue:@(posStart)];
        [slide setToValue:@(posEnd)];
        [slide setDuration:AnimationDuration];
        [[_contentView layer] addAnimation:slide forKey:AnimationName];
        [[_contentView layer] setValue:@(posEnd) forKeyPath:@"position.x"];
        
        
        
        CABasicAnimation* fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        [fade setTimingFunction:[CAMediaTimingFunction functionWithName:AnimationTimingFunction]];
        [fade setFromValue:@0];
        [fade setToValue:@1];
        [fade setDuration:AnimationDuration];
        [[_contentView layer] addAnimation:fade forKey:nil];
        [[_contentView layer] setValue:@1 forKeyPath:@"opacity"];
        
        
    }
}

- (void)_sourceListTrackResize:(NSEvent*)event {
    ImageGridView* imageGridView = CastOrNil<ImageGridView>(_contentView);
    _dragging = true;
    [[self window] invalidateCursorRectsForView:self];
    [imageGridView setResizingUnderway:true];
    
    const CGFloat offsetX =
        [_resizerView bounds].size.width/2 - [_resizerView convertPoint:[event locationInWindow] fromView:nil].x;
    
    TrackMouse([self window], event, [&](NSEvent* event, bool done) {
        const CGFloat desiredWidth = [self convertPoint:[event locationInWindow] fromView:nil].x + offsetX;
        const CGFloat width = std::max(SourceListWidth::Min, desiredWidth);
        
        if (desiredWidth<SourceListWidth::HideThreshold && _sourceListVisible) {
            NSLog(@"HIDE");
            [_sourceListWidth setConstant:0];
            _sourceListVisible = false;
        } else if (desiredWidth>=SourceListWidth::HideThreshold && !_sourceListVisible) {
            NSLog(@"SHOW");
            [_sourceListWidth setConstant:width];
            _sourceListVisible = true;
        } else if (_sourceListVisible) {
            [_sourceListWidth setConstant:width];
        }
        
        [_sourceListMinWidth setActive:_sourceListVisible];
    });
    
    _dragging = false;
    [[self window] invalidateCursorRectsForView:self];
    [imageGridView setResizingUnderway:false];
}

- (void)resetCursorRects {
    if (_dragging) {
        [self addCursorRect:[self bounds] cursor:_resizerView->cursor];
    }
}

- (void)animationDidStop:(CAAnimation*)anim finished:(BOOL)flag {
    
}

@end

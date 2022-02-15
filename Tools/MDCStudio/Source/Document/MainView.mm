#import "MainView.h"
#import <algorithm>
#import "SourceList/SourceListView.h"
#import "Util.h"
#import "ImageGrid/ImageGridView.h"
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
        [[self layer] setBackgroundColor:[[NSColor colorWithSRGBRed:.118 green:.122 blue:.129 alpha:1] CGColor]];
    }
    
    // Create source list
    {
        __weak auto weakSelf = self;
        _sourceListView = [[SourceListView alloc] initWithFrame:{}];
        [_sourceListView setSelectionChangedHandler:^(SourceListView*) {
            [weakSelf _sourceListHandleSelectionChanged];
        }];
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
    
    // Handle whatever is first selected
    {
        [self _sourceListHandleSelectionChanged];
    }
}

- (SourceListView*)sourceListView {
    return _sourceListView;
}

- (NSView*)contentView {
    return _contentView;
}

- (void)setContentView:(NSView*)contentView {
    if (_contentView) {
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

- (void)_sourceListHandleSelectionChanged {
    auto selection = [_sourceListView selection];
    if (selection.device) {
        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageLibrary:selection.device->imgLib()];
        [self setContentView:imageGridView];
    
    } else {
        [self setContentView:nil];
    }
}

- (void)resetCursorRects {
    if (_dragging) {
        [self addCursorRect:[self bounds] cursor:_resizerView->cursor];
    }
}

@end

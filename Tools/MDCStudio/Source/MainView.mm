#import "MainView.h"
#import "SourceList/SourceListView.h"

@implementation MainView {
    SourceListView* _sourceListView;
    NSLayoutConstraint* _sourceListWidth;
    
    NSView* _contentContainerView;
    NSView* _contentView;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    abort();
    return [super initWithCoder:coder]; // Silence warning
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _sourceListView = [[SourceListView alloc] initWithFrame:{}];
    [self addSubview:_sourceListView];
    
    constexpr CGFloat SourceListWidthMin = 150;
    constexpr CGFloat SourceListWidthDefault = 300;
    [self addConstraint:[NSLayoutConstraint constraintWithItem:_sourceListView attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
        multiplier:0 constant:SourceListWidthMin]];    
    
    _sourceListWidth = [NSLayoutConstraint constraintWithItem:_sourceListView attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
        multiplier:0 constant:SourceListWidthDefault];
    [_sourceListWidth setPriority:NSLayoutPriorityDefaultHigh];
    [self addConstraint:_sourceListWidth];
    
    _contentContainerView = [[NSView alloc] initWithFrame:{}];
    
    [_contentContainerView setWantsLayer:true];
    [[_contentContainerView layer] setBackgroundColor:[[[NSColor redColor] colorWithAlphaComponent:.2] CGColor]];
    
    [_contentContainerView setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addSubview:_contentContainerView];
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_sourceListView][_contentContainerView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_sourceListView, _contentContainerView)]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_sourceListView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_sourceListView)]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_contentContainerView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_contentContainerView)]];
    
    return self;
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
    [_contentView setTranslatesAutoresizingMaskIntoConstraints:false];
    [_contentContainerView addSubview:contentView];
    [_contentContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_contentView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_contentView)]];
    [_contentContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_contentView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_contentView)]];
}

@end

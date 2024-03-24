#import "ImageGridContainerView.h"
#import "ImageGridView/ImageGridView.h"
using namespace MDCStudio;

@implementation ImageGridContainerView {
    ImageGridView* _imageGridView;
    ImageGridScrollView* _imageGridScrollView;
}

- (instancetype)initWithImageGridView:(ImageGridView*)imageGridView {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    _imageGridView = imageGridView;
    _imageGridScrollView = [[ImageGridScrollView alloc] initWithAnchoredDocument:_imageGridView];
    [self addSubview:_imageGridScrollView];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_imageGridScrollView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_imageGridScrollView)]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_imageGridScrollView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_imageGridScrollView)]];
    
    return self;
}

- (ImageGridView*)imageGridView {
    return _imageGridView;
}

- (ImageGridScrollView*)imageGridScrollView {
    return _imageGridScrollView;
}

@end

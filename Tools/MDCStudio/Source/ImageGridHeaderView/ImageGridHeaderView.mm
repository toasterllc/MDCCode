#import "ImageGridHeaderView.h"

@implementation ImageGridHeaderView {
    id<ImageGridHeaderViewDelegate> _delegate;
    IBOutlet NSView* _nibView;
    
    IBOutlet NSLayoutConstraint* _height;
    
    IBOutlet NSTextField* _statusLabel;
    
    IBOutlet NSView* _loadPhotosContainerView;
    IBOutlet NSTextField* _loadPhotosCountLabel;
}

static void _InitCommon(ImageGridHeaderView* self) {
    // Load view from nib
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    NSView* nibView = self->_nibView;
    [nibView setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addSubview:nibView];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
    
    [self setLoadCount:0];
    
//    [self setWantsLayer:true];
//    [[self layer] setBackgroundColor:[[NSColor colorWithSRGBRed:.110 green:.113 blue:.113 alpha:.7] CGColor]];
//    [[self layer] setBackgroundColor:[[[NSColor blackColor] colorWithAlphaComponent:.7] CGColor]];
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _InitCommon(self);
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _InitCommon(self);
    return self;
}

- (CGFloat)height {
    return [_height constant];
}

- (void)setDelegate:(id<ImageGridHeaderViewDelegate>)x {
    _delegate = x;
}

- (void)setLoadCount:(NSUInteger)x {
    if (x) {
        [_statusLabel setStringValue:[NSString stringWithFormat:@"%@", @(x)]];
        [_loadPhotosContainerView setHidden:false];
    } else {
        [_loadPhotosContainerView setHidden:true];
    }
}

- (IBAction)load:(id)sender {
    [_delegate imageGridHeaderViewLoad:self];
}

@end

#import "LoadPhotosView.h"

@implementation LoadPhotosView {
    id<LoadPhotosViewDelegate> _delegate;
    IBOutlet NSView* _nibView;
    IBOutlet NSTextField* _label;
    IBOutlet NSLayoutConstraint* _height;
}

static void _InitCommon(LoadPhotosView* self) {
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

- (void)setDelegate:(id<LoadPhotosViewDelegate>)x {
    _delegate = x;
}

- (void)setLoadCount:(NSUInteger)x {
    [_label setStringValue:[NSString stringWithFormat:@"%@", @(x)]];
}

- (IBAction)load:(id)sender {
    [_delegate loadPhotosViewLoad:self];
}

@end

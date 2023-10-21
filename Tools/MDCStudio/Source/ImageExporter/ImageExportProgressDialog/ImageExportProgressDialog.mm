#import "ImageExportProgressDialog.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@implementation ImageExportProgressDialog {
    IBOutlet NSView* _nibView;
    IBOutlet NSProgressIndicator* _progressBar;
    __weak id<ImageExportProgressDialogDelegate> _delegate;
}

- (instancetype)init {
    if (!(self = [super initWithContentRect:{} styleMask:0 backing:NSBackingStoreBuffered defer:true])) return nil;
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    [self setContentView:_nibView];
    return self;
}

- (void)setProgress:(float)x {
    
}

- (void)setDelegate:(id<ImageExportProgressDialogDelegate>)x {
    _delegate = x;
}


- (IBAction)_cancel:(id)sender {
    
}
@end

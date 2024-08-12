#import "SettingsWindow.h"
#import "NibViewInit.h"

using namespace MDCStudio;

//@interface SettingsView : NSView
//@end
//
//@implementation SettingsView {
//    IBOutlet NSView* _nibView;
//}
//
//- (instancetype)init {
//    if (!(self = [super initWithFrame:{}])) return nil;
//    // Load view from nib
//    NibViewInit(self, _nibView);
//    return self;
//}
//
//@end

@implementation SettingsWindow

- (instancetype)init {
    NSArray* topLevelObjects = nil;
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:nil topLevelObjects:&topLevelObjects];
    assert(br);
    assert([topLevelObjects count] == 1);
    id window = topLevelObjects[0];
    assert([window isKindOfClass:[SettingsWindow class]]);
    return window;
}

@end

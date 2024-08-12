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
    NSArray* objects = nil;
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:nil topLevelObjects:&objects];
    assert(br);
    for (id obj : objects) {
        if ([obj isKindOfClass:[self class]]) return obj;
    }
    abort();
}

@end

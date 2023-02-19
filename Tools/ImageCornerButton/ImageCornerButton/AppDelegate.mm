#import "AppDelegate.h"
#import "ImageCornerButton.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (IBAction)clicked:(id)sender {
    NSLog(@"clicked %@", @((int)[(ImageCornerButton*)sender corner]));
}

@end




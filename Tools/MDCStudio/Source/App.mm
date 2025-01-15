#import <Cocoa/Cocoa.h>
#import "Shared/MDCDevicesManager.h"
#import "SettingsWindow/SettingsWindow.h"
#import "Shared/PrefsUtil.h"
using namespace MDCStudio;

@interface App : NSApplication
@end

@implementation App {
    SettingsWindow* _settingsWindow;
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    NSLog(@"[Document] validateUserInterfaceItem: %@\n", item);
    NSMenuItem* mitem = Toastbox::CastOrNull<NSMenuItem*>(item);
    
    // Save
    if ([item action] == @selector(_toggleTimestamp:)) {
        [mitem setState:(PrefsUtil::Timestamp::Visible() ? NSControlStateValueOn : NSControlStateValueOff)];
        return true;
    }
    return true;
}

- (IBAction)orderFrontStandardAboutPanel:(id)sender {
    [super orderFrontStandardAboutPanelWithOptions:@{
        // Suppress the build number because we use the same number for both the application version
        // and build number, so it's redundant
        NSAboutPanelOptionVersion: @"",
    }];
}

- (IBAction)_showSettingsWindow:(id)sender {
    if (!_settingsWindow) _settingsWindow = [SettingsWindow new];
    [_settingsWindow makeKeyAndOrderFront:self];
//    [super showSettingsWindow]
}

- (IBAction)_toggleTimestamp:(id)sender {
    PrefsUtil::Timestamp::Visible(!PrefsUtil::Timestamp::Visible());
}

- (NSAppearance*)appearance {
    return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate {
    Object::ObserverPtr _devicesChangedObserver;
}

- (void)_handleDeviceIncompatibleVersion:(const MDCUSBDevice::IncompatibleVersion&)e {
    NSAlert* alert = [NSAlert new];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert setMessageText:@"Incompatible Photon"];
    [alert setInformativeText:[NSString stringWithFormat:@"A Photon was connected that is running firmware that is too new for this version of Photon Transfer.\n\nPlease use a newer version of Photon Transfer.\n\nError: %s", e.what()]];
    [alert runModal];
}

- (void)_handleNewDevices:(const std::set<MDCDeviceHardPtr>&)devices {
    for (MDCDeviceHardPtr dev : devices) {
        dev->sync();
    }
}

- (void)applicationWillFinishLaunching:(NSNotification*)note {
    __weak auto selfWeak = self;
    MDCDevicesManager::IncompatibleVersionHandler handler = [=] (const MDCUSBDevice::IncompatibleVersion& e) {
        MDCUSBDevice::IncompatibleVersion ecopy = e;
        dispatch_async(dispatch_get_main_queue(), ^{
            [selfWeak _handleDeviceIncompatibleVersion:ecopy];
        });
    };
    
    MDCDevicesManagerGlobal(Object::Create<MDCDevicesManager>(handler));
    _devicesChangedObserver = MDCDevicesManagerGlobal()->observerAdd([=] (auto, const Object::Event& ev2) {
        const MDCDevicesManager::Change& ev = static_cast<const MDCDevicesManager::Change&>(ev2);
        if (!ev.added.empty()) {
            [selfWeak _handleNewDevices:ev.added];
        }
    });
    
    [self _handleNewDevices:MDCDevicesManagerGlobal()->devices()];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    // no_destroy attribute is required, otherwise DeviceLocks would be destroyed and
    // relinquish the locks, which is exactly what we don't want to do! The locks need
    // to be held throughout termination to prevent device IO, to ensure the device is
    // kept out of host mode.
    [[clang::no_destroy]]
    static std::vector<std::unique_lock<std::mutex>> DeviceLocks;
    
    // Ensure that all devices are out of host mode when we exit, by acquiring each device's
    // device lock and stashing the locks in our global DeviceLocks.
    MDCDevicesManagerPtr devicesManager = MDCDevicesManagerGlobal();
    const std::set<MDCDeviceHardPtr> devices = devicesManager->devices();
    for (MDCDeviceHardPtr device : devices) {
        try {
            auto lock = device->deviceLock(true);
            DeviceLocks.push_back(std::move(lock));
        } catch (const Toastbox::Signal::Stop&) {
            // Ignore if the device has been stopped
        }
    }
    printf("applicationShouldTerminate\n");
    return NSTerminateNow;
}

@end

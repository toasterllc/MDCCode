#import "DeviceSettingsSheet.h"
#import "DeviceSettingsView.h"

@implementation DeviceSettingsSheet

- (instancetype)initWithView:(DeviceSettingsView*)view {
    if (!(self = [super initWithContentRect:{} styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:false])) {
        return nil;
    }
    
    NSView* contentView = [self contentView];
    [contentView addSubview:view];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|"
        options:0 metrics:nil views:@{@"view":view}]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|"
        options:0 metrics:nil views:@{@"view":view}]];
    return self;
}

- (NSRect)constrainFrameRect:(NSRect)frame toScreen:(NSScreen*)screen {
    NSWindow* parent = [self sheetParent];
    NSRect parentFrame = [parent frame];
    NSRect rect = [super constrainFrameRect:frame toScreen:screen];
    if (@available(macOS 11, *)) {
        rect.origin = {
            CGRectGetMidX(parentFrame) - rect.size.width/2,
            CGRectGetMaxY(parentFrame) - rect.size.height - 25,
        };
    }
    return rect;
}

@end

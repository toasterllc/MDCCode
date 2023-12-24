#import "FactoryResetConfirmationAlert.h"
#import "NibViewInit.h"
using namespace MDCStudio;

NSString* ConfirmationPhrase = @"nuke it";

@implementation FactoryResetConfirmationAlert {
    IBOutlet NSView* _accessoryView;
    IBOutlet NSView* _accessoryTextFieldContainer;
    IBOutlet NSView* _accessorySpinnerContainer;
    IBOutlet NSTextField* _accessoryTextField;
    IBOutlet NSProgressIndicator* _accessorySpinner;
    FactoryResetConfirmationAlertHandler _handler;
    NSButton* _okButton;
    NSButton* _cancelButton;
    bool _spinnerVisible;
    __weak id _dismissTarget;
    SEL _dismissAction;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [self setAlertStyle:NSAlertStyleWarning];
    [self setMessageText:@"Factory Reset"];
    [self setInformativeText:[NSString stringWithFormat:@"A factory reset will permanently erase all photos and settings from your Photon.\n\nTo continue, enter “%@” below.", ConfirmationPhrase]];
    {
        NSButton* button = [self addButtonWithTitle:@"OK"];
        [button setTag:NSModalResponseOK];
        [button setTarget:self];
        [button setAction:@selector(_ok:)];
        _okButton = button;
    }
    {
        NSButton* button = [self addButtonWithTitle:@"Cancel"];
        _dismissTarget = [button target];
        _dismissAction = [button action];
        [button setTag:NSModalResponseCancel];
        [button setTarget:self];
        [button setAction:@selector(_cancel:)];
        _cancelButton = button;
    }
    
    [_accessoryTextField setPlaceholderString:ConfirmationPhrase];
    [self setAccessoryView:_accessoryView];
    
    [self layout];
    [[_accessoryTextField window] makeFirstResponder:_accessoryTextField];
    
    [self _update];
    
    return self;
}

- (void)beginSheetModalForWindow:(NSWindow*)window
completionHandler:(FactoryResetConfirmationAlertHandler)handler {
    
    _handler = handler;
    [super beginSheetModalForWindow:window completionHandler:nil];
}

- (void)setSpinnerVisible:(bool)x {
    _spinnerVisible = x;
    [self _update];
}

- (void)dismiss {
    [NSApp sendAction:_dismissAction to:_dismissTarget from:_cancelButton];
}

- (IBAction)_ok:(id)sender {
    _handler(NSModalResponseOK);
}

- (IBAction)_cancel:(id)sender {
    _handler(NSModalResponseCancel);
}

- (void)_update {
    if (_spinnerVisible) {
        [_okButton setEnabled:false];
        [_cancelButton setEnabled:false];
    } else {
        [_okButton setEnabled:[[_accessoryTextField stringValue] isEqualToString:ConfirmationPhrase]];
        [_cancelButton setEnabled:true];
    }
    
    [_accessoryTextFieldContainer setHidden:_spinnerVisible];
    [_accessorySpinnerContainer setHidden:!_spinnerVisible];
    if (_spinnerVisible) [_accessorySpinner startAnimation:nil];
    else                 [_accessorySpinner stopAnimation:nil];
}

- (void)controlTextDidChange:(NSNotification*)obj {
    [self _update];
}

@end

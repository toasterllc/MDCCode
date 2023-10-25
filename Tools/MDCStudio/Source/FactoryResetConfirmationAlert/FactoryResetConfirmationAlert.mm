#import "FactoryResetConfirmationAlert.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@interface FactoryResetConfirmationAlertAccessoryView : NSView
@end

@implementation FactoryResetConfirmationAlertAccessoryView {
    IBOutlet NSView* _nibView;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NibViewInit(self, _nibView);
    return self;
}

@end

NSString* ConfirmationPhrase = @"nuke it";

@implementation FactoryResetConfirmationAlert {
    IBOutlet NSView* _accessoryView;
    IBOutlet NSTextField* _accessoryTextField;
    NSButton* _okButton;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    [self setAlertStyle:NSAlertStyleWarning];
    [self setMessageText:@"Factory Reset"];
    [self setInformativeText:[NSString stringWithFormat:@"A factory reset will permanently erase all photos and settings from your Photon.\n\nTo continue, enter “%@” below.", ConfirmationPhrase]];
    [self addButtonWithTitle:@"OK"];
    [[[self buttons] lastObject] setTag:NSModalResponseOK];
    [self addButtonWithTitle:@"Cancel"];
    [[[self buttons] lastObject] setTag:NSModalResponseCancel];
    
    _okButton = [self buttons][0];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [_accessoryTextField setPlaceholderString:ConfirmationPhrase];
    [self setAccessoryView:_accessoryView];
    
    [self _okButtonUpdate];
    
    [self layout];
    [[_accessoryTextField window] makeFirstResponder:_accessoryTextField];
    
//    NSTextField* field = [[NSTextField alloc] initWithFrame:{100,20}];
//    [field setAutoresizingMask:
//        NSViewMinXMargin|NSViewMaxXMargin|
//        NSViewMinYMargin|NSViewMaxYMargin|
//        NSViewWidthSizable];
//    [self setAccessoryView:field];
    
//    FactoryResetConfirmationAlertAccessoryView* accessoryView =
//        [[FactoryResetConfirmationAlertAccessoryView alloc] initWithFrame:{}];
//    [self setAccessoryView:accessoryView];
//    [self layout];
    
//    NSView* superview = [accessoryView superview];
//    [superview setTranslatesAutoresizingMaskIntoConstraints:false];
//    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[accessoryView]|"
//        options:0 metrics:nil views:NSDictionaryOfVariableBindings(accessoryView)]];
//    
//    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[accessoryView]|"
//        options:0 metrics:nil views:NSDictionaryOfVariableBindings(accessoryView)]];
    
    
    
//    {
//        NSTextView *accessory = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,200,15)];
//        NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
//        NSDictionary *textAttributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
//        [accessory insertText:[[NSAttributedString alloc] initWithString:@"Text in accessory view." attributes:textAttributes]];
//        [accessory setEditable:NO];
//        [accessory setDrawsBackground:NO];
//        
//        
//        [self setAccessoryView:accessory];
//    }
    
    return self;
}

- (void)_okButtonUpdate {
    [_okButton setEnabled:[[_accessoryTextField stringValue] isEqualToString:ConfirmationPhrase]];
}

- (void)controlTextDidChange:(NSNotification*)obj {
    [self _okButtonUpdate];
}

@end

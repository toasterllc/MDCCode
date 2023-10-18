#pragma once

namespace MDCStudio {

inline void NibViewInit(NSView* self, NSView*const& nibView) {
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [self addSubview:nibView];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
}

} // namespace MDCStudio

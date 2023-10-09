#import "BatteryLifeView.h"
#import "BatteryLifeEstimate.h"
using namespace MDCStudio;
using namespace BatteryLifeViewTypes;

namespace T = BatteryLifeViewTypes;

@implementation BatteryLifeView {
@public
    __weak id<BatteryLifeViewDelegate> _delegate;
    
    IBOutlet NSView* _nibView;
    IBOutlet NSPopUpButton* _motionIntervalButton;
    IBOutlet NSPopUpButton* _buttonIntervalButton;
    
    MSP::Triggers _triggers;
    std::optional<T::BatteryLifeEstimate> _batteryLifeEstimate;
}

static void _PopulateIntervalMenu(NSMenu* menu) {
    [menu removeAllItems];
    15 seconds
    30 seconds
    1 minute
    3 minutes
    5 minutes
    10 minutes
    15 minutes
    30 minutes
    1 hour
}

static void _Init(BatteryLifeView* self) {
    // Load view from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        NSView* nibView = self->_nibView;
        [nibView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:nibView];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
    }
    
    [[self->_motionIntervalButton menu] removeAllItems];
    
}

// MARK: - Creation

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _Init(self);
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _Init(self);
    return self;
}

- (BOOL)acceptsFirstResponder {
    return true;
}

- (void)cancelOperation:(id)sender {
    [[self window] performClose:nil];
}

- (void)setDelegate:(id<BatteryLifeViewDelegate>)delegate {
    _delegate = delegate;
}

- (void)setTriggers:(const MSP::Triggers&)triggers {
    _triggers = triggers;
    _batteryLifeEstimate = std::nullopt;
    [_delegate batteryLifeViewChanged:self];
}

- (T::BatteryLifeEstimate)batteryLifeEstimate {
    [self _updateBatteryLifeEstimateIfNeeded];
    return *_batteryLifeEstimate;
}

- (std::chrono::seconds)_motionStimulusInterval {
    return std::chrono::seconds(0);
}

- (std::chrono::seconds)_buttonStimulusInterval {
    return std::chrono::seconds(0);
}

- (void)_updateBatteryLifeEstimateIfNeeded {
    if (_batteryLifeEstimate) return;
//    Estimator(const Constants& consts,
//        const Parameters& params,
//        const MSP::Triggers& triggers) : _consts(consts), _params(params), _triggers(triggers) {
//    
//    const std::chrono::seconds motionStimulusInterval = std::chrono::seconds(0);
//    const std::chrono::seconds buttonStimulusInterval = std::chrono::seconds(0);
    
    const MDCStudio::BatteryLifeEstimate::Parameters parameters = {
        .motionStimulusInterval = [self _motionStimulusInterval],
        .buttonStimulusInterval = [self _buttonStimulusInterval],
    };
    MDCStudio::BatteryLifeEstimate::Estimator estimatorMin(
        MDCStudio::BatteryLifeEstimate::WorstCase, parameters, _triggers);
    MDCStudio::BatteryLifeEstimate::Estimator estimatorMax(
        MDCStudio::BatteryLifeEstimate::BestCase, parameters, _triggers);
    
    estimatorMin.estimate();
    estimatorMax.estimate();
}

@end

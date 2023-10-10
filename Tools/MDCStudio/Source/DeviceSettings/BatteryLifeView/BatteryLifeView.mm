#import "BatteryLifeView.h"
#import "BatteryLifeSimulator.h"
#import "Prefs.h"
#import "BatteryLifePlotView.h"
#import "Code/Lib/Toastbox/Defer.h"
#import "Code/Lib/Toastbox/String.h"
#import "Code/Lib/Toastbox/NumForStr.h"
using namespace MDCStudio;
using namespace BatteryLifeViewTypes;

namespace T = BatteryLifeViewTypes;
namespace DS = DeviceSettings;

@implementation BatteryLifeView {
@public
    __weak id<BatteryLifeViewDelegate> _delegate;
    
    IBOutlet NSView* _nibView;
    IBOutlet BatteryLifePlotView* _minPlotView;
    IBOutlet BatteryLifePlotView* _maxPlotView;
    IBOutlet NSLayoutConstraint* _minPlotViewWidth;
    IBOutlet NSLayoutConstraint* _maxPlotViewWidth;
    IBOutlet NSTextField* _motionIntervalField;
    IBOutlet NSPopUpButton* _motionIntervalMenu;
    IBOutlet NSTextField* _buttonIntervalField;
    IBOutlet NSPopUpButton* _buttonIntervalMenu;
    IBOutlet NSTextField* _batteryLifeMinLabel;
    IBOutlet NSTextField* _batteryLifeMaxLabel;
    
    bool _storeLoadUnderway;
    MSP::Triggers _triggers;
    std::optional<T::BatteryLifeEstimate> _estimate;
}

static DS::Duration _StimulusIntervalGet(std::string key, const DS::Duration& uninit) {
    namespace DS = DeviceSettings;
    try {
        DS::Duration dur = DS::DurationFromString(PrefsGlobal().get(key, ""));
        dur.value = std::max(1.f, dur.value);
        return dur;
    } catch (std::exception& e) {
        return uninit;
    }
}

static void _StimulusIntervalSet(std::string key, const DS::Duration& dur) {
    namespace DS = DeviceSettings;
    PrefsGlobal().set(key, std::to_string(dur.value) + " " + DS::Duration::StringFromUnit(dur.unit));
}

static DS::Duration _MotionStimulusInterval() {
    MDCStudio::BatteryLifeSimulator::Constants consts;
    return _StimulusIntervalGet("MotionStimulusInterval",
        DS::DurationFromSeconds(consts.motionStimulusInterval));
}

static void _MotionStimulusInterval(const DS::Duration& x) {
    _StimulusIntervalSet("MotionStimulusInterval", x);
}

static DS::Duration _ButtonStimulusInterval() {
    MDCStudio::BatteryLifeSimulator::Constants consts;
    return _StimulusIntervalGet("ButtonStimulusInterval",
        DS::DurationFromSeconds(consts.buttonStimulusInterval));
}

static void _ButtonStimulusInterval(const DS::Duration& x) {
    _StimulusIntervalSet("ButtonStimulusInterval", x);
}

// MARK: - Creation

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    
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
    
    [[_maxPlotView plotLayer] setFillColor:[[NSColor colorWithSRGBRed:.184 green:.510 blue:.922 alpha:1] CGColor]];
    [[_minPlotView plotLayer] setFillColor:[[[NSColor blackColor] colorWithAlphaComponent:.4] CGColor]];
    
    __weak auto selfWeak = self;
    PrefsGlobal().observerAdd([=] () {
        auto selfStrong = selfWeak;
        if (!selfStrong) return false;
        [selfStrong _prefsChanged];
        return true;
    });
    
    _Load(self);
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        NSLog(@"first responder: %@", [[self window] firstResponder]);
//    }];
    
    return self;
}

template<bool T_Forward>
static void _Copy(DS::Duration& x, NSTextField* field, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        [field setStringValue:@(DS::StringFromFloat(x.value).c_str())];
        [menu selectItemWithTitle:@(DS::Duration::StringFromUnit(x.unit).c_str())];
    } else {
        const std::string xstr = [[menu titleOfSelectedItem] UTF8String];
        try {
            x.value = std::max(0.f, DS::FloatFromString([[field stringValue] UTF8String]));
        } catch (...) {}
        x.unit = DS::Duration::UnitFromString([[menu titleOfSelectedItem] UTF8String]);
    }
}

static void _Store(BatteryLifeView* self) {
    {
        DS::Duration x;
        _Copy<false>(x, self->_motionIntervalField, self->_motionIntervalMenu);
        _MotionStimulusInterval(x);
    }
    
    {
        DS::Duration x;
        _Copy<false>(x, self->_buttonIntervalField, self->_buttonIntervalMenu);
        _ButtonStimulusInterval(x);
    }
}

static void _Load(BatteryLifeView* self) {
    {
        DS::Duration x = _MotionStimulusInterval();
        _Copy<true>(x, self->_motionIntervalField, self->_motionIntervalMenu);
    }
    {
        DS::Duration x = _ButtonStimulusInterval();
        _Copy<true>(x, self->_buttonIntervalField, self->_buttonIntervalMenu);
    }
}

static void _StoreLoad(BatteryLifeView* self) {
//    // Prevent re-entry, because our committing logic can trigger multiple calls
//    if (self->_actionViewChangedUnderway) return;
//    self->_actionViewChangedUnderway = true;
//    Defer( self->_actionViewChangedUnderway = false );
    
    // Prevent re-entry, because our committing logic can trigger multiple calls
    if (self->_storeLoadUnderway) return;
    self->_storeLoadUnderway = true;
    Defer( self->_storeLoadUnderway = false );
    
    _Store(self);
    _Load(self);
}

//- (BOOL)acceptsFirstResponder {
//    return true;
//}

- (IBAction)_actionViewChanged:(id)sender {
    _StoreLoad(self);
    [self _update];
    [_delegate batteryLifeViewChanged:self];
}

//- (void)cancelOperation:(id)sender {
//    [[self window] performClose:nil];
//}

- (void)setDelegate:(id<BatteryLifeViewDelegate>)delegate {
    _delegate = delegate;
}

- (void)setTriggers:(const MSP::Triggers&)triggers {
    _triggers = triggers;
    [self _update];
    [_delegate batteryLifeViewChanged:self];
}

- (T::BatteryLifeEstimate)batteryLifeEstimate {
    [self _updateIfNeeded];
    return *_estimate;
}

- (void)_prefsChanged {
    if (_storeLoadUnderway) return;
    _Load(self);
    [self _update];
    [_delegate batteryLifeViewChanged:self];
}

- (void)_update {
    const MDCStudio::BatteryLifeSimulator::Constants constants = {
        .motionStimulusInterval = SecondsFromDuration(_MotionStimulusInterval()),
        .buttonStimulusInterval = SecondsFromDuration(_ButtonStimulusInterval()),
    };
    
    MDCStudio::BatteryLifeSimulator::Simulator simMin(
        constants, MDCStudio::BatteryLifeSimulator::WorstCase, _triggers);
    MDCStudio::BatteryLifeSimulator::Simulator simMax(
        constants, MDCStudio::BatteryLifeSimulator::BestCase, _triggers);
    
    const auto pointsMin = simMin.estimate();
    const auto pointsMax = simMax.estimate();
    assert(!pointsMin.empty());
    assert(!pointsMax.empty());
    
    // Update battery life estimate
    _estimate = {
        .min = pointsMin.back().time,
        .max = pointsMax.back().time,
    };
    
    // Update plot
    [_minPlotView setPoints:pointsMin];
    [_maxPlotView setPoints:pointsMax];
    
    // Set min plot view width
    const CGFloat factor = (CGFloat)pointsMin.back().time.count() /
        pointsMax.back().time.count();
    [_minPlotViewWidth setConstant:factor*[_maxPlotViewWidth constant]];
    
    // Update labels
    [_batteryLifeMinLabel setStringValue:@(DeviceSettings::StringForDuration(_estimate->min).c_str())];
    [_batteryLifeMaxLabel setStringValue:@(DeviceSettings::StringForDuration(_estimate->max).c_str())];
}

- (void)_updateIfNeeded {
    if (_estimate) return;
    [self _update];
}

@end

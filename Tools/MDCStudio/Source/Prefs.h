#import <Foundation/Foundation.h>

namespace MDCStudio {

class Prefs {
public:
    static bool SortNewestFirst() {
        return [_Defaults() boolForKey:@(_SortNewestFirst::Key)];
    }
    
    static void SortNewestFirst(bool x) {
        [_Defaults() setBool:x forKey:@(_SortNewestFirst::Key)];
    }
    
private:
    struct _SortNewestFirst {
        static constexpr const char*     Key = "SortNewestFirst";
        static constexpr bool        Default = true;
    };
    
    static NSUserDefaults* _DefaultsCreate() {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        [defaults registerDefaults:@{
            @(_SortNewestFirst::Key): @(_SortNewestFirst::Default),
        }];
        return defaults;
    }
    
    static NSUserDefaults* _Defaults() {
        static NSUserDefaults* x = _DefaultsCreate();
        return x;
    }
};

} // namespace MDCStudio

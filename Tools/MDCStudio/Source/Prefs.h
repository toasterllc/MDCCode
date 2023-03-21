#import <Foundation/Foundation.h>
#import "Toastbox/Mac/Util.h"

namespace MDCStudio {

class Prefs {
private:
    // _defaults: needs to be initialized before all other members, so put it at the top
    NSUserDefaults* _defaults = [NSUserDefaults new];
    
public:
    using Observer = std::function<bool()>;
    
//    Prefs() : _defaults([NSUserDefaults new]) {
//        assert([NSThread isMainThread]);
//        _Init(_defaults, _sortNewestFirst);
//    }
//    
//    ~Prefs() {
//        assert([NSThread isMainThread]);
//    }
//    
//    struct SortNewestFirst {
//        static constexpr const char* Key = "SortNewestFirst";
//        bool                         value = true;
//    };
    
    bool _sortNewestFirst           = _get("SortNewestFirst", true);
    bool sortNewestFirst() const    { return _sortNewestFirst; }
    void sortNewestFirst(bool x)    { _set("SortNewestFirst", _sortNewestFirst, x); }
    
    void observerAdd(Observer&& observer) {
        _observers.push_front(std::move(observer));
    }
    
private:
    template <class...> static constexpr std::false_type _AlwaysFalse;
    
    template<typename T>
    static T _Load(NSUserDefaults* defaults, const char* key) {
        return Toastbox::CastOrNull<T>([defaults objectForKey:@(key)]);
    }
    
    template<typename T>
    T _get(const char* key, const T& uninit) {
        if (auto x = _Load<NSNumber*>(_defaults, key)) {
            if constexpr (std::is_same_v<T, bool>) {
                return [x boolValue];
            } else {
                static_assert(_AlwaysFalse<T>);
            }
        }
        return uninit;
    }
    
    template<typename T>
    void _set(const char* key, T& t, const T& x) {
        t = x;
        [_defaults setObject:@(t) forKey:@(key)];
        _notify();
    }
    
    // notify(): notifies each observer that we changed
    void _notify() {
        auto prev = _observers.before_begin();
        for (auto it=_observers.begin(); it!=_observers.end();) {
            // Notify the observer; it returns whether it's still valid
            // If it's not valid (it returned false), remove it from the list
            if (!(*it)()) {
                it = _observers.erase_after(prev);
            } else {
                prev = it;
                it++;
            }
        }
    }
    
    std::forward_list<Observer> _observers;
};

inline Prefs& PrefsGlobal() {
    static Prefs x;
    return x;
}

} // namespace MDCStudio

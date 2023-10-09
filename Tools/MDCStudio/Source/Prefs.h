#import <Foundation/Foundation.h>
#import "Toastbox/Mac/Util.h"
#import <forward_list>

namespace MDCStudio {

class Prefs {
private:
    // _defaults: needs to be initialized before all other members, so put it at the top
    NSUserDefaults* _defaults = [NSUserDefaults new];
    
public:
    using Observer = std::function<bool()>;
    
    template<typename T>
    T get(std::string_view key, const T& uninit) {
        // Numeric types
        if constexpr (std::is_arithmetic_v<T>) {
            return _getArithmetic(key, uninit);
        } else if constexpr (std::is_same_v<T, const char*> || std::is_same_v<T, std::string>) {
            return _getString(key, uninit);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return uninit;
    }
    
    template<typename T>
    void set(std::string_view key, const T& x) {
        if constexpr (std::is_arithmetic_v<T>) {
            [_defaults setObject:@(x) forKey:@(std::string(key).c_str())];
        } else if constexpr (std::is_same_v<T, const char*>) {
            [_defaults setObject:@(x) forKey:@(std::string(key).c_str())];
        } else if constexpr (std::is_same_v<T, std::string>) {
            [_defaults setObject:@(x.c_str()) forKey:@(std::string(key).c_str())];
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        
        _notify();
    }
    
    void observerAdd(Observer&& observer) {
        _observers.push_front(std::move(observer));
    }
    
private:
    template <class...> static constexpr std::false_type _AlwaysFalse;
    
    template<typename T>
    static T _Load(NSUserDefaults* defaults, std::string_view key) {
        return Toastbox::CastOrNull<T>([defaults objectForKey:@(std::string(key).c_str())]);
    }
    
    template<typename T>
    T _getArithmetic(std::string_view key, const T& uninit) {
        if (auto x = _Load<NSNumber*>(_defaults, key)) {
            if constexpr (std::is_same_v<T, bool>) {
                return [x boolValue];
            } else if constexpr (std::is_unsigned_v<T>) {
                return [x unsignedLongLongValue];
            } else if constexpr (std::is_signed_v<T>) {
                return [x longLongValue];
            } else if constexpr (std::is_same_v<T, float>) {
                return [x floatValue];
            } else if constexpr (std::is_same_v<T, double>) {
                return [x doubleValue];
            } else {
                static_assert(_AlwaysFalse<T>);
            }
        }
        return uninit;
    }
    
    template<typename T>
    T _getString(std::string_view key, const T& uninit) {
        if (auto x = _Load<NSString*>(_defaults, key)) {
            if constexpr (std::is_same_v<T, const char*>) {
                return [x UTF8String];
            } else if constexpr (std::is_same_v<T, std::string>) {
                return std::string([x UTF8String]);
            } else {
                static_assert(_AlwaysFalse<T>);
            }
        }
        return uninit;
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

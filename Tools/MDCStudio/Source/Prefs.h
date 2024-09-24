#import <Foundation/Foundation.h>
#import <forward_list>
#import <optional>
#import "Code/Lib/Toastbox/Mac/Util.h"
#import "Object.h"

namespace MDCStudio {

struct Prefs : Object {
    struct Event : Object::Event {
        std::string key;
    };
    
    // _defaults: needs to be initialized before all other members, so put it at the top
    NSUserDefaults* _defaults = [NSUserDefaults new];
    
    template<typename T>
    std::optional<T> get(std::string_view key) {
        // Numeric types
        if constexpr (std::is_arithmetic_v<T>) {
            return _getArithmetic<T>(key);
        } else if constexpr (std::is_enum_v<T>) {
            auto x = _getArithmetic<std::underlying_type_t<T>>(key);
            if (!x) return std::nullopt;
            return (T)*_getArithmetic<std::underlying_type_t<T>>(key);
        } else if constexpr (std::is_same_v<T, const char*> || std::is_same_v<T, std::string>) {
            return _getString<T>(key);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return std::nullopt;
    }
    
    template<typename T>
    T get(std::string_view key, T uninit) {
        return get<T>(key).value_or(uninit);
    }
    
    template<typename T>
    void set(std::string_view key, const T& x) {
        if constexpr (std::is_arithmetic_v<T>) {
            [_defaults setObject:@(x) forKey:@(std::string(key).c_str())];
        } else if constexpr (std::is_enum_v<T>) {
            [_defaults setObject:@((std::underlying_type_t<T>)x) forKey:@(std::string(key).c_str())];
        } else if constexpr (std::is_same_v<T, const char*>) {
            [_defaults setObject:@(x) forKey:@(std::string(key).c_str())];
        } else if constexpr (std::is_same_v<T, std::string>) {
            [_defaults setObject:@(x.c_str()) forKey:@(std::string(key).c_str())];
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        
        Event ev;
        ev.key = key;
        observersNotify(ev);
    }
    
    template<class...> static constexpr std::false_type _AlwaysFalse;
    
    template<typename T>
    static T _Load(NSUserDefaults* defaults, std::string_view key) {
        return Toastbox::CastOrNull<T>([defaults objectForKey:@(std::string(key).c_str())]);
    }
    
    template<typename T>
    std::optional<T> _getArithmetic(std::string_view key) {
        if (auto x = _Load<NSNumber*>(_defaults, key)) {
            if constexpr (std::is_same_v<T, bool>) {
                return [x boolValue];
            } else if constexpr (std::is_same_v<T, float>) {
                return [x floatValue];
            } else if constexpr (std::is_same_v<T, double>) {
                return [x doubleValue];
            } else if constexpr (std::is_unsigned_v<T>) {
                return [x unsignedLongLongValue];
            } else if constexpr (std::is_signed_v<T>) {
                return [x longLongValue];
            } else {
                static_assert(_AlwaysFalse<T>);
            }
        }
        return std::nullopt;
    }
    
    template<typename T>
    std::optional<T> _getString(std::string_view key) {
        if (auto x = _Load<NSString*>(_defaults, key)) {
            if constexpr (std::is_same_v<T, const char*>) {
                return [x UTF8String];
            } else if constexpr (std::is_same_v<T, std::string>) {
                return std::string([x UTF8String]);
            } else {
                static_assert(_AlwaysFalse<T>);
            }
        }
        return std::nullopt;
    }
};
using PrefsPtr = SharedPtr<Prefs>;

inline PrefsPtr PrefsGlobal() {
    static PrefsPtr x = Object::Create<Prefs>();
    return x;
}

} // namespace MDCStudio

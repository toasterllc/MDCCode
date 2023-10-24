#pragma once
#include <string>
#include <vector>
#include <list>
#include <set>
#include <map>
#include <simd/simd.h>
#include <cxxabi.h>
#include "Toastbox/Cast.h"

namespace MDCStudio {

#define ObjectInit(typ, super)                  \
    virtual ~typ() {                            \
        printf("~%s\n", debugClassName());      \
    }                                           \
                                                \
    void init() {                               \
        super::init();                          \
    }

// ObjectPropertyValue: property with value semantics.
// Thread-safe.
#define ObjectPropertyValue(typ, name, init...)                       \
    typ _##name = { init };                                           \
    virtual typ name() { return _getter<false>(_##name); }            \
    virtual void name(typ x) { _setter<false>(_##name, std::move(x)); }

// ObjectPropertyReference: property with reference semantics.
// Not thread-safe; client responsible for thread safety.
#define ObjectPropertyReference(typ, name, init...)                  \
    typ _##name = { init };                                          \
    virtual const typ& name() { return _getter<true>(_##name); }     \
    virtual void name(typ x) { _setter<true>(_##name, std::move(x)); }

// SharedPtr: shared_ptr wrapper that adds implicit casting to remove the need for explicit casts
template<typename T>
struct SharedPtr : std::shared_ptr<T> {
    using _Super = std::shared_ptr<T>;
    
    using std::shared_ptr<T>::shared_ptr;
    
    // Construct SharedPtr / shared_ptr with same underlying type: no cast required; null is allowed
    template<
    typename X,
    typename std::enable_if_t<std::is_same_v<T,X> || std::is_base_of_v<T,X>, int> = 0
    >
    SharedPtr(const SharedPtr<X>& x) : _Super(x) {}
    
    template<
    typename X,
    typename std::enable_if_t<std::is_same_v<T,X> || std::is_base_of_v<T,X>, int> = 0
    >
    SharedPtr(const std::shared_ptr<X>& x) : _Super(x) {}
    
    // Construct SharedPtr / shared_ptr with different underlying type: cast required; null not allowed
    template<
    typename X,
    typename std::enable_if_t<!(std::is_same_v<T,X> || std::is_base_of_v<T,X>), int> = 0
    >
    SharedPtr(const SharedPtr<X>& x) : _Super(Toastbox::Cast<_Super>(x)) {}
    
    template<
    typename X,
    typename std::enable_if_t<!(std::is_same_v<T,X> || std::is_base_of_v<T,X>), int> = 0
    >
    SharedPtr(const std::shared_ptr<X>& x) : _Super(Toastbox::Cast<_Super>(x)) {}
    
    // as() explicit cast where null is allowed
    template<typename X>
    X as() { return Toastbox::CastOrNull<X>(*this); }
    
    template<typename X>
    X as() const { return Toastbox::CastOrNull<X>(*this); }
};










struct Object; using ObjectPtr = SharedPtr<Object>;
struct Object {
    // MARK: - Creation
    template<typename T, typename... T_Args>
    static SharedPtr<T> Create(T_Args&&... args) {
        SharedPtr<T> r = std::make_shared<T>();
        r->init(std::forward<T_Args>(args)...);
        assert(r->_initDebug); // Debug: ensure that subclasses bubbled init() all the way up
        return r;
    }
    
    // init(): called immediately after construction
    void init() { _initDebug = true; }
    bool _initDebug = false;
    
    // MARK: - Observation
    
    struct Event {
        virtual ~Event() {} // Allow polymorphism
        // prop: the address of the property that changed
        const void* prop = nullptr;
    };
    
    using Observer    = std::function<void(const Event&)>;
    using ObserverPtr = SharedPtr<Observer>;
    
    static ObserverPtr ObserverCreate(Observer&& fn) {
        return std::make_shared<Observer>(std::move(fn));
    }
    
    ObserverPtr observerAdd(Observer&& fn) {
        ObserverPtr ob = ObserverCreate(std::move(fn));
        observerAdd(ob);
        return ob;
    }
    
    bool observerAdd(ObserverPtr ob) {
        _observersPrune(std::unique_lock(_observe.lock));
        auto [_,inserted] = _observe.observers.insert(ob);
        return inserted;
    }
    
    bool observerRemove(ObserverPtr ob) {
        auto lock = std::unique_lock(_observe.lock);
        return _observe.observers.erase(ob);
    }
    
    void observersNotify(const Event& ev) {
        std::set<ObserverPtr::weak_type,std::owner_less<>> observers;
        {
            auto lock = std::unique_lock(_observe.lock);
            observers = _observe.observers;
        }
        
        changed(ev);
        
        for (auto obWeak : _observe.observers) {
            ObserverPtr ob = obWeak.lock();
            if (ob) (*ob)(ev);
        }
    }
    
    // changed: allows subclasses to monitor all events, as if it's an observer
    virtual void changed(const Event& ev) {}
    
    // _observersPrune(): observe.lock must be held
    void _observersPrune(const std::unique_lock<std::mutex>& lock) {
        // Prune observers
        auto it = _observe.observers.begin();
        while (it != _observe.observers.end()) {
            ObserverPtr ob = (*it).lock();
            if (!ob) {
                // Null -> prune
                it = _observe.observers.erase(it);
            } else {
                it++;
            }
        }
    }
    
    struct {
        std::mutex lock; // Protects this struct
        std::set<ObserverPtr::weak_type,std::owner_less<>> observers;
    } _observe;
    
    // MARK: - Debug
    
    const char* debugClassName() const {
        int status = 0;
        char* demangled = abi::__cxa_demangle(typeid(*this).name(), 0, 0, &status);
        assert(!status);
        return demangled;
    }
    
    // _Equal(): default implementation
    template<
    typename T,
    typename std::enable_if_t<std::is_scalar_v<T>, int> = 0
    >
    static bool _Equal(const T& a, const T& b) {
        return a == b;
    }
    
    static bool _Equal(const std::string& a, const std::string& b) {
        return a == b;
    }
    
    static bool _Equal(const simd::float2& a, const simd::float2& b) {
        return simd::all(a == b);
    }
    
    static bool _Equal(const simd::float3& a, const simd::float3& b) {
        return simd::all(a == b);
    }
    
    static bool _Equal(const simd::float4& a, const simd::float4& b) {
        return simd::all(a == b);
    }
    
    template<typename T>
    static bool _Equal(const std::shared_ptr<T>& a, const std::shared_ptr<T>& b) {
        return a == b;
    }
    
    template<typename, typename=void>
    struct _EqualExists : std::false_type {};
    
    template<typename T>
    struct _EqualExists<T, std::void_t<decltype(_Equal(std::declval<T>(),std::declval<T>()))>> : std::true_type {};
    
    template<
    typename T,
    typename std::enable_if_t<std::is_base_of_v<Object,T>, int> = 0
    >
    static void __IsObjectPtr(std::shared_ptr<T>) {}

    template<typename, typename=void>
    struct _IsObjectPtr : std::false_type {};

    template<typename T>
    struct _IsObjectPtr<T, std::void_t<decltype(__IsObjectPtr(std::declval<T>()))>> : std::true_type {};
    
    template<bool T_Ref, typename T>
    std::conditional_t<T_Ref, const T&, T> _getter(const T& prop) {
        std::unique_lock<std::mutex> lock;
        if constexpr (T_Ref) {
            lock = std::unique_lock(_propLock);
        }
        return prop;
    }
    
    template<bool T_Ref, typename T>
    void _setter(T& prop, T x) {
        bool changed = false;
        {
            std::unique_lock<std::mutex> lock;
            if constexpr (T_Ref) {
                lock = std::unique_lock(_propLock);
            }
            // Check equality if the type supports it
            if constexpr (_EqualExists<T>::value) {
                if (!_Equal(prop, x)) {
                    prop = std::move(x);
                    changed = true;
                }
            } else {
                prop = std::move(x);
                changed = true;
            }
        }
        
        if (changed) {
            Event ev;
            ev.prop = &prop;
            observersNotify(ev);
        }
    }
    
    std::mutex _propLock;
};

} // namespace MDCStudio

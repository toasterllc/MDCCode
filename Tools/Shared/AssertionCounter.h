#pragma once
struct AssertionCounter {
    using Fn = std::function<void(bool)>;
    using FnPtr = std::shared_ptr<Fn>;
    
    struct _Assertion {
        _Assertion(FnPtr fn) : _fn(fn) { (*_fn)(true); }
        ~_Assertion() { (*_fn)(false); }
        FnPtr _fn;
    };
    using Assertion = std::shared_ptr<_Assertion>;
    
    AssertionCounter(Fn fn=[](bool){}) : _fn(std::make_shared<Fn>(std::move(fn))) {}
    
    Assertion assertion() {
        auto strong = _assertion.lock();
        if (!strong) {
            strong = std::make_shared<_Assertion>(_fn);
            _assertion = strong;
        }
        return strong;
    }
    
    FnPtr _fn;
    std::weak_ptr<_Assertion> _assertion;
};

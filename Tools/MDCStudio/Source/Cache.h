#pragma once
#include <memory>
#include <vector>
#include "LRU.h"
#include "Signal.h"

template<typename T_Key, typename T_Val, size_t T_Cap>
class Cache {
public:
    struct _Cookie {
        _Cookie(Cache& cache, size_t idx) : cache(cache), idx(idx) {}
        ~_Cookie() { cache._recycle(idx); }
        Cache& cache;
        const size_t idx = 0;
    };
    
    struct Wrapper {
        Wrapper() {}
        Wrapper(Cache& cache, size_t idx) : _val(&cache._mem[idx]), _cookie(std::make_shared<_Cookie>(cache, idx)) {}
        T_Val* operator->() const { return _val; }
        T_Val& operator*() const { return *_val; }
        T_Val* _val = nullptr;
        std::shared_ptr<_Cookie> _cookie;
    };
    
    Cache(size_t count) {
//        _count = count;
//        _mem = std::make_unique<uint8_t[]>(count * T_BufSize);
//        for (size_t i=0; i<count; i++) {
//            _free.push_back(_mem.get() + (i*T_BufSize));
//        }
        for (size_t i=0; i<T_Cap;i++) {
            _free.push_back(i);
        }
    }
    
    ~Cache() {
        // Verify that there are no outstanding entries when we're destroyed
        assert(_free.size()+_lru.size() == T_Cap);
    }
    
    // get(): find an existing entry
    Wrapper get(const T_Key& key) {
        auto lock = _signal.lock();
        if (auto find=_lru.find(key); find!=_lru.end()) {
            return find->val;
        }
        return {};
    }
    
    // set(): set an entry for a key
    void set(const T_Key& key, const Wrapper& val) {
        auto lock = _signal.lock();
        _lru[key] = val;
    }
    
    Wrapper pop() {
        auto lock = _signal.lock();
        if (_free.empty()) {
            _lru.evict();
            _signal.wait(lock, [&] { return !_free.empty(); });
        }
        
        const size_t idx = _free.back();
        _free.pop_back();
        return Wrapper(*this, idx);
    }
    
    void _recycle(size_t idx) {
        {
            auto lock = _signal.lock();
            _free.push_back(idx);
        }
        _signal.signalOne();
    }
    
    
    
    
    
    
    
    
//private:
    Toastbox::Signal _signal;
    T_Val _mem[T_Cap];
    Toastbox::LRU<T_Key,Wrapper,T_Cap> _lru;
    std::vector<size_t> _free;
};

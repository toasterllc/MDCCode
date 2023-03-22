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
        operator bool() { return _val; }
        T_Val* operator->() const { return _val; }
        T_Val& operator*() const { return *_val; }
        T_Val* _val = nullptr;
        std::shared_ptr<_Cookie> _cookie;
    };
    
    Cache() {
//        _count = count;
//        _mem = std::make_unique<uint8_t[]>(count * T_BufSize);
//        for (size_t i=0; i<count; i++) {
//            _free.push_back(_mem.get() + (i*T_BufSize));
//        }
        for (size_t i=0; i<T_Cap;i++) {
            _free.list.push_back(i);
        }
    }
    
    ~Cache() {
        // Verify that there are no outstanding entries when we're destroyed
        assert(_free.list.size()+_cache.lru.size() == T_Cap);
    }
    
    // get(): find an existing entry for a key
    // If the entry didn't exist, (bool)Wrapper == false
    Wrapper get(const T_Key& key) {
        auto lock = std::unique_lock(_cache.lock);
        if (auto find=_cache.lru.find(key); find!=_cache.lru.end()) {
            return find->val;
        }
        return {};
    }
    
    // set(): set an entry for a key
    void set(const T_Key& key, Wrapper val) {
        auto lock = std::unique_lock(_cache.lock);
        _cache.lru[key] = val;
    }
    
    Wrapper pop() {
        auto lock = _free.signal.wait([&] { return !_free.list.empty(); });
        const size_t idx = _free.list.back();
        _free.list.pop_back();
        return Wrapper(*this, idx);
    }
    
    
    
    
    
    
    
    
    
//    #warning TODO: pop(): there's potential for deadlock here if the free list is empty and all outstanding Wrapper aren't in the cache.
//    Wrapper pop() {
//        auto lock = _free.signal.lock();
//        for (;;) {
//            if (!_free.list.empty()) {
//                const size_t idx = _free.list.back();
//                _free.list.pop_back();
//                return Wrapper(*this, idx);
//            }
//            lock.unlock();
//            
//            {
//                auto lock = std::unique_lock(_cache.lock);
//                _cache.lru.evict();
//            }
//            
//            lock.lock();
//            _free.signal.wait(lock, [&] { return !_free.list.empty(); });
//        }
//    }
    
    
    
//    #warning TODO: pop(): there's potential for deadlock here if the free list is empty and all
//    Wrapper pop() {
//        if (_freeListEmpty()) {
//            {
//                auto lock = std::unique_lock(_cache.lock);
//                _cache.lru.evict();
//            }
//        }
//        
//        auto lock = _free.signal.wait([&] { return !_free.list.empty(); });
//        const size_t idx = _free.list.back();
//        _free.list.pop_back();
//        return Wrapper(*this, idx);
//    }
    
    bool _freeListEmpty() {
        auto lock = _free.signal.lock();
        return _free.list.empty();
    }
    
    void _recycle(size_t idx) {
        {
            auto lock = _free.signal.lock();
            _free.list.push_back(idx);
        }
        _free.signal.signalOne();
    }
    
    
    
    
    
    
    
    
//private:
    
    T_Val _mem[T_Cap];
    
    // _free: needs to be decalred before _cache, so that upon destruction, _free persists longer
    // than _cache, since the Wrappers that are destroyed as a part of _cache.lru being destroyed
    // need _free to exist for _recycle() to work properly.
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::vector<size_t> list;
    } _free;
    
    struct {
        std::mutex lock; // Protects this struct;
        Toastbox::LRU<T_Key,Wrapper,T_Cap-8> lru;
    } _cache;
};

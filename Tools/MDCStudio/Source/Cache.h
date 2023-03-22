#pragma once
#include <memory>
#include <vector>
#include "Toastbox/LRU.h"
#include "Toastbox/Signal.h"

template<typename T_Key, typename T_Val, size_t T_Cap>
class Cache {
public:
    struct _Cookie {
        _Cookie(Cache& cache, size_t idx) : cache(cache), idx(idx) {}
        ~_Cookie() { cache._recycle(idx); }
        Cache& cache;
        const size_t idx = 0;
    };
    
    struct Val {
        Val() {}
        Val(Cache& cache, size_t idx) : _val(&cache._mem[idx]), _cookie(std::make_shared<_Cookie>(cache, idx)) {}
        operator bool() { return _val; }
        bool operator<(const Val& x) const { return _cookie < x._cookie; }
        bool operator==(const Val& x) const { return _cookie == x._cookie; }
        bool operator!=(const Val& x) const { return _cookie != x._cookie; }
        T_Val* operator->() const { return _val; }
        T_Val& operator*() const { return *_val; }
        T_Val* _val = nullptr;
        std::shared_ptr<_Cookie> _cookie;
    };
    
    Cache() {
        for (size_t i=0; i<T_Cap;i++) {
            _free.list.push_back(i);
        }
    }
    
    ~Cache() {
        // Verify that there are no outstanding entries when we're destroyed
        assert(_free.list.size()+_cache.lru.size() == T_Cap);
    }
    
    std::unique_lock<std::mutex> lock() {
        return std::unique_lock(_cache.lock);
    }
    
    // get(): find an existing entry for a key
    // If the entry didn't exist, (bool)Val == false
    Val get(std::unique_lock<std::mutex>& lock, const T_Key& key) {
        assert(lock);
        if (auto find=_cache.lru.find(key); find!=_cache.lru.end()) {
            return find->val;
        }
        return {};
    }
    
    // set(): set an entry for a key
    void set(std::unique_lock<std::mutex>& lock, const T_Key& key, Val val) {
        assert(lock);
        _cache.lru[key] = val;
    }
    
    // pop(): return an empty entry
    Val pop(std::unique_lock<std::mutex>& lock) {
        assert(lock);
        _free.signal.wait(lock, [&] { return !_free.list.empty(); });
        const size_t idx = _free.list.back();
        _free.list.pop_back();
        return Val(*this, idx);
    }
    
    void evict(std::unique_lock<std::mutex>& lock) {
        assert(lock);
        _cache.lru.evict();
    }
    
    size_t size(std::unique_lock<std::mutex>& lock) const {
        assert(lock);
        return _cache.lru.size();
    }
    
    size_t sizeFree(std::unique_lock<std::mutex>& lock) {
        // We need `lock` to be held to prevent removals from the free-list, so that our
        // return value indicates the minimum free list size as long as the lock is held.
        // We still need to acquire _free.signal.lock() though to safely access _free.list.
        assert(lock);
        auto l = _free.signal.lock();
        return _free.list.size();
    }
    
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
    
    Val get(const T_Key& key) {
        auto l = lock();
        return get(l, key);
    }
    
    void set(const T_Key& key, Val val) {
        auto l = lock();
        set(l, key, val);
    }
    
    Val pop() {
        auto l = lock();
        return pop(l);
    }
    
    void evict() {
        auto l = lock();
        return evict(l);
    }
    
    size_t size() {
        auto l = lock();
        return size(l);
    }
    
    size_t sizeFree() {
        auto l = lock();
        return sizeFree(l);
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
    
    // _free: needs to be declared before _cache, so that upon destruction, _free persists longer
    // than _cache, since the Vals that are destroyed as a part of _cache.lru being destroyed
    // need _free to exist for _recycle() to work properly.
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::vector<size_t> list;
    } _free;
    
    struct {
        std::mutex lock; // Protects this struct;
        Toastbox::LRU<T_Key,Val,T_Cap-8> lru;
    } _cache;
};

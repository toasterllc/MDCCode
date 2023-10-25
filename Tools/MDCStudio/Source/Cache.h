#pragma once
#include <memory>
#include <vector>
#include "Toastbox/LRU.h"
#include "Toastbox/Signal.h"

template<typename T_Key, typename T_Val, size_t T_Cap, uint8_t T_PriorityLast=0>
struct Cache {
    struct _Entry {
        _Entry(Cache& cache, size_t idx) : cache(cache), idx(idx) {}
        ~_Entry() { cache._destroy(*this); }
        Cache& cache;
        const size_t idx = 0;
    };
    
    struct Entry {
        Entry() {}
        Entry(Cache& cache, size_t idx) : val(&cache._mem[idx]), shared(std::make_shared<_Entry>(cache, idx)) {}
        operator bool() const { return val; }
        bool operator<(const Entry& x) const { return shared < x.shared; }
        bool operator==(const Entry& x) const { return shared == x.shared; }
        bool operator!=(const Entry& x) const { return shared != x.shared; }
        T_Val* operator->() const { return val; }
        T_Val& operator*() const { return *val; }
        T_Val* val = nullptr;
        std::shared_ptr<_Entry> shared;
    };
    
    struct Reserved {
        Reserved() {}
        Reserved(Cache& cache, size_t idx, uint8_t priority) : _state{.entry=Entry(cache, idx), .priority=priority} {}
        // Copy
        Reserved(const Reserved& x) = delete;
        Reserved& operator=(const Reserved& x) = delete;
        // Move
        Reserved(Reserved&& x) { swap(x); }
        Reserved& operator=(Reserved&& x) { swap(x); return *this; }
        ~Reserved() { if (_state.entry) _state.entry.shared->cache._destroy(*this); }
        
        const Entry& entry() const { return _state.entry; }
        
//        operator const Entry&() const { return _state.entry; }
//        bool operator<(const Reserved& x) const { return _state.entry < x._state.entry; }
//        bool operator==(const Reserved& x) const { return _state.entry == x._state.entry; }
//        bool operator!=(const Reserved& x) const { return _state.entry != x._state.entry; }
        
        void swap(Reserved& x) {
            std::swap(_state, x._state);
        }
        
        struct {
            Entry entry;
            size_t priority = 0;
        } _state;
    };
    
    Cache() {
        uint8_t priority = 0;
        for (size_t i=0; i<T_Cap; i++, priority++) {
            if (priority > T_PriorityLast) priority = 0;
            _free.list.push_back(i);
            _free.counter[priority]++;
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
    Entry get(std::unique_lock<std::mutex>& lock, const T_Key& key) {
        assert(lock);
        if (auto find=_cache.lru.find(key); find!=_cache.lru.end()) {
            return find->val;
        }
        return {};
    }
    
    // set(): set an entry for a key
    Entry set(std::unique_lock<std::mutex>& lock, const T_Key& key, Reserved&& reserved) {
        assert(lock);
        Entry& entry = _cache.lru[key];
        entry = reserved.entry();
        return entry;
    }
    
    // pop(): return an empty entry
    Reserved pop(std::unique_lock<std::mutex>& lock, uint8_t priority=0) {
        // We don't use `lock` but it allows the caller to implement atomicity across
        // multiple operations.
        // We do need to acquire _free.signal.lock() though to safely access _free.list.
        assert(lock);
        assert(priority <= T_PriorityLast);
        for (;;) {
            auto& counter = _free.counter[priority];
            
            bool evikt = false;
            {
                auto l = _free.signal.lock();
                // If the priority has slots available, and the free list isn't empty, return a Reserved.
                // If the priority has slots available, but the free list is empty, evict entries to try
                // to free up slots.
                // If the priority doesn't have slots available, wait until it does.
                if (counter) {
                    if (!_free.list.empty()) {
                        const size_t idx = _free.list.back();
                        _free.list.pop_back();
                        counter--;
                        return Reserved(*this, idx, priority);
                    } else {
                        evikt = true;
                    }
                }
            }
            
            // Try to free up space
            // We say try because we can evict an Entry from the LRU, but the client may still hold
            // a reference to the Entry, so the slot won't be added to the free list until the
            // client loses its reference to the Entry.
            if (evikt) evict(lock);
            
            // Don't hold _cache.lock while we block waiting for a free slot, because we don't
            // want to prevent the cache from being used while we block.
            // Note that we can't use the lock returned from wait() because we have to re-acquire
            // _cache.lock, and if we used the lock returned by wait() we'd be prone to deadlock
            // due to acquiring the two locks out of order. (Ie we normally acquire _cache.lock
            // first, followed by _free.signal, but in this case we'd be acquiring _free.signal
            // first, followed by _cache.lock.)
            lock.unlock();
            _free.signal.wait([&] { return counter && !_free.list.empty(); });
            lock.lock();
        }
    }
    
    // evict(): tells the underlying LRU to evict the oldest entries
    void evict(std::unique_lock<std::mutex>& lock) {
        assert(lock);
        _cache.lru.evict();
    }
    
    void clear(std::unique_lock<std::mutex>& lock) {
        assert(lock);
        _cache.lru.clear();
    }
    
    // size(): returns the current number of entries stored in the cache
    size_t size(std::unique_lock<std::mutex>& lock) const {
        assert(lock);
        return _cache.lru.size();
    }
    
    // sizeFree(): returns the number of unoccupied entries in the cache
    // This indicates the number of times that pop() can be called without blocking.
    size_t sizeFree(std::unique_lock<std::mutex>& lock, uint8_t priority=0) {
        // We need `lock` to be held even though we don't use it, because it prevents
        // removals from the free-list (via pop), so that our return value indicates the
        // minimum free list size as long as the lock is held. We still need to acquire
        // _free.signal.lock() though to safely access _free.list.
        assert(lock);
        assert(priority <= T_PriorityLast);
        auto l = _free.signal.lock();
        return _free.counter[priority];
    }
    
    Entry get(const T_Key& key) {
        auto l = lock();
        return get(l, key);
    }
    
    Entry set(const T_Key& key, Reserved&& reserved) {
        auto l = lock();
        return set(l, key, std::move(reserved));
    }
    
    Reserved pop(uint8_t priority=0) {
        auto l = lock();
        return pop(l, priority);
    }
    
    void evict() {
        auto l = lock();
        return evict(l);
    }
    
    void clear() {
        auto l = lock();
        return clear(l);
    }
    
    size_t size() {
        auto l = lock();
        return size(l);
    }
    
    size_t sizeFree(uint8_t priority=0) {
        auto l = lock();
        return sizeFree(l, priority);
    }
    
    auto& mem() {
        return _mem;
    }
    
    void _destroy(const _Entry& x) {
        {
            auto lock = _free.signal.lock();
            _free.list.push_back(x.idx);
        }
        _free.signal.signalOne();
    }
    
    void _destroy(const Reserved& x) {
        {
            auto lock = _free.signal.lock();
            _free.counter[x._state.priority]++;
        }
        _free.signal.signalOne();
    }
    
    // _Headroom: set the capacity of our LRU to slightly smaller than T_Cap, to ensure that
    // if the LRU is full, we still have available slots for pop() to use without blocking.
    // This ensures that pop() doesn't need eviction logic to guarantee that it can return a
    // slot without blocking, provided the headroom isn't exhausted due to outstanding Val's
    // held by the client.
    static constexpr size_t _Headroom = std::max((size_t)1, T_Cap/64);
    
    T_Val _mem[T_Cap];
    
    // _free: needs to be declared before _cache, so that upon destruction, _free persists longer
    // than _cache, since the Vals that are destroyed as a part of _cache.lru being destroyed
    // need _free to exist for _destroy() to work properly.
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::vector<size_t> list;
        size_t counter[T_PriorityLast+1] = {};
    } _free;
    
    struct {
        std::mutex lock; // Protects this struct;
        Toastbox::LRU<T_Key,Entry,T_Cap-_Headroom> lru;
    } _cache;
};

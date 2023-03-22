#pragma once
#include <memory>
#include <vector>

template<size_t T_BufSize>
class BufferPool {
public:
    using Pointer = uint8_t*;
    
    struct _Cookie {
        _Cookie(BufferPool& pool, Pointer ptr) : pool(pool), ptr(ptr) {}
        ~_Cookie() { pool._recycle(ptr); }
        BufferPool& pool;
        const Pointer ptr;
    };
    
    struct Buffer {
        Buffer() {}
        Buffer(BufferPool& pool, Pointer ptr) : _ptr(ptr), _cookie(std::make_shared<_Cookie>(pool, ptr)) {}
        operator Pointer() const { return _ptr; }
        Pointer _ptr = nullptr;
        std::shared_ptr<_Cookie> _cookie;
    };
    
    BufferPool(size_t count) {
        _count = count;
        _mem = std::make_unique<uint8_t[]>(count * T_BufSize);
        for (size_t i=0; i<count; i++) {
            _free.push_back(_mem.get() + (i*T_BufSize));
        }
    }
    
    ~BufferPool() {
        // Verify that there are no outstanding buffers when we're destroyed
        assert(_free.size() == _count);
    }
    
    Buffer pop() {
        assert(!_free.empty());
        const Pointer ptr = _free.back();
        _free.pop_back();
        return Buffer(*this, ptr);
    }
    
    bool empty() const { return _free.empty(); }
    
    void _recycle(Pointer ptr) {
        _free.push_back(ptr);
    }
    
private:
    size_t _count = 0;
    std::unique_ptr<uint8_t[]> _mem;
    std::vector<Pointer> _free;
};

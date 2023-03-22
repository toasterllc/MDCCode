#pragma once
#include <memory>
#include <vector>

template<size_t T_BufSize>
class BufferPool {
public:
    using Pointer = uint8_t*;
    struct Buffer {
        Buffer() {}
        Buffer(BufferPool& pool, Pointer ptr) : _state({.pool=&pool, .ptr=ptr}) {}
        
        // Copy
        Buffer(const Buffer& x) = delete;
        Buffer& operator=(const Buffer& x) = delete;
        // Move
        Buffer(Buffer&& x) { swap(x); }
        Buffer& operator=(Buffer&& x) { swap(x); return *this; }
        
        ~Buffer() {
            if (_state.pool) {
                _state.pool->_recycle(_state.ptr);
            }
        }
        
        operator Pointer() const { return _state.data; }
        
        void swap(Buffer& x) {
            std::swap(_state, x._state);
        }
        
        struct {
            BufferPool* pool = nullptr;
            Pointer ptr = nullptr;
        } _state;
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

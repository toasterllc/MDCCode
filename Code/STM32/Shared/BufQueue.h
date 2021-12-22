#pragma once

// BufQueue:
//   BufQueue manages `T_Count` buffers to facilitate
//   producer-consumer schemes.
//   
//   If the BufQueue is !full(), the writer writes into
//   the buffer returned by front(), and when writing is
//   complete, calls push().
//   
//   If the BufQueue is !empty(), the reader reads from the
//   buffer returned by back(), and when reading is
//   complete, calls pop().

template <typename T_Type, size_t T_Cap, size_t T_Count>
class BufQueue {
public:
    struct Buf {
        T_Type data[T_Cap];
        size_t len = 0;
    };
    
    // Read
    bool empty() const { return _w==_r && !_full; }
    
    Buf& front() {
        Assert(!empty());
        return _bufs[_r];
    }
    
    void pop() {
        Assert(!empty());
        _r++;
        if (_r == T_Count) _r = 0;
        _full = false;
    }
    
    // Write
    bool full() const { return _full; }
    
    Buf& back() {
        Assert(!full());
        return _bufs[_w];
    }
    
    void push() {
        Assert(!full());
        _w++;
        if (_w == T_Count) _w = 0;
        if (_w == _r) _full = true;
    }
    
    // Reset
    void reset() {
        for (Buf& buf : _bufs) buf.len = 0;
        
        _w = 0;
        _r = 0;
        _full = false;
    }
    
private:
    Buf _bufs[T_Count];
    size_t _w = 0;
    size_t _r = 0;
    bool _full = false;
};

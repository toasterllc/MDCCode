#pragma once

// BufQueue:
//   BufQueue manages `T_Count` buffers to facilitate
//   producer-consumer schemes.
//   
//   If the BufQueue is writable (wok()==true), the writer writes
//   into the buffer returned by wget(), and when writing is
//   complete, calls wpush().
//   
//   If the BufQueue is readable (rok()==true), the reader reads
//   from the buffer returned by rget(), and when reading is
//   complete, calls rpop().

template <typename T_Type, size_t T_Cap, size_t T_Count, auto T_Assert=nullptr>
class BufQueue {
public:
    struct Buf {
        T_Type data[T_Cap];
        size_t len = 0;
    };
    
    // Read
    bool rok() const { return _w!=_r || _full; }
    
    Buf& rget() {
        _Assert(rok());
        return _bufs[_r];
    }
    
    void rpop() {
        _Assert(rok());
        _r++;
        if (_r == T_Count) _r = 0;
        _full = false;
    }
    
    // Write
    bool wok() const { return !_full; }
    
    Buf& wget() {
        _Assert(wok());
        return _bufs[_w];
    }
    
    void wpush() {
        _Assert(wok());
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
    
    static void _Assert(bool c) {
        if constexpr (!std::is_same<decltype(T_Assert), std::nullptr_t>::value) {
            T_Assert(c);
        }
    }
};

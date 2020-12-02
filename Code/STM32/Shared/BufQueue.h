#pragma once

// BufQueue:
//   BufQueue manages `Count` static buffers (supplied to the
//   constructor) to facilitate producer-consumer schemes.
//
//   The writer writes into the buffer returned by writeBuf(),
//   and when writing is complete, calls writeEnqueue().
//
//   The reader reads from the buffer returned by readBuf(),
//   and when reading is complete, calls readDequeue().

template <size_t Count>
class BufQueue {
private:
    struct Buf {
        uint8_t* data = nullptr;
        size_t cap = 0;
        size_t len = 0;
    };
    
public:
    template <typename... Ts>
    BufQueue(Ts&... bufs) {
        static_assert(sizeof...(bufs) == Count, "invalid number of buffers");
        _init(bufs...);
    }
    
    // Reading
    bool readable() const { return _w!=_r || _full; }
    
    const Buf& readBuf() const {
        Assert(readable());
        return _bufs[_r];
    }
    
    void readDequeue() {
        Assert(readable());
        _r++;
        if (_r == Count) _r = 0;
        _full = false;
    }
    
    // Writing
    bool writable() const { return !_full; }
    
    Buf& writeBuf() {
        Assert(writable());
        return _bufs[_w];
    }
    
    void writeEnqueue() {
        Assert(writable());
        _w++;
        if (_w == Count) _w = 0;
        if (_w == _r) _full = true;
    }
    
private:
    Buf _bufs[Count];
    size_t _w = 0;
    size_t _r = 0;
    bool _full = false;
    
    template <typename T>
    void _init(T& buf) {
        constexpr size_t idx = Count-1;
        _bufs[idx].data = buf;
        _bufs[idx].cap = sizeof(buf);
    }
    
    template <typename T, typename... Ts>
    void _init(T& buf, Ts&... bufs) {
        constexpr size_t idx = Count-sizeof...(bufs)-1;
        _bufs[idx].data = buf;
        _bufs[idx].cap = sizeof(buf);
        _init(bufs...);
    }
};

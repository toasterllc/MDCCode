#pragma once

// BufQueue:
//   BufQueue manages `Count` static buffers (supplied to the
//   constructor) to facilitate producer-consumer schemes.
//
//   If the BufQueue is writable(), the writer writes into
//   the buffer returned by writeBuf(), and when writing is
//   complete, calls writeEnqueue().
//
//   If the BufQueue is readable(), the reader reads from the
//   buffer returned by readBuf(), and when reading is
//   complete, calls readDequeue().

template <size_t Count>
class BufQueue {
private:
    struct Buf {
        template <typename T>
        Buf(T& buf) : data(buf), cap(sizeof(buf)) {}
        uint8_t*const data = nullptr;
        const size_t cap = 0;
        size_t len = 0;
    };
    
public:
    template <typename... Ts>
    BufQueue(Ts&... bufs) : _bufs{bufs...} {
        static_assert(Count && sizeof...(bufs)==Count, "invalid number of buffers");
    }
    
    // Read
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
    
    // Write
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
    
    // Reset
    void reset() {
        _w = 0;
        _r = 0;
        _full = false;
    }
    
private:
    Buf _bufs[Count];
    size_t _w = 0;
    size_t _r = 0;
    bool _full = false;
};

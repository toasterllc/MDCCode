#pragma once

// BufQueue:
//   BufQueue provides `Count` static buffers, each of size `Size`,
//   to facilitate producer-consumer schemes.
//
//   The writer writes into the buffer returned by writeBuf(),
//   and when writing is complete, calls writeEnqueue().
//
//   The reader reads from the buffer returned by readBuf(),
//   and when reading is complete, calls readDequeue().

template <size_t Size, size_t Count>
class BufQueue {
private:
    struct Buf {
        uint8_t data[Size] __attribute__((aligned(4)));
        size_t len = 0;
    };
    
public:
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
};

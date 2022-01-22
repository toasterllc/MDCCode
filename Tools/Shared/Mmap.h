#pragma once
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>
#include <stdexcept>
#include <string>
#include <cstring>
#include <filesystem>
#include <unistd.h>
#include "Toastbox/RuntimeError.h"
#include "Toastbox/FileDescriptor.h"

class Mmap {
public:
    Mmap() {}
    
    Mmap(FileDescriptor&& fd, int flags=MAP_PRIVATE) {
        try {
            _init(std::move(fd), flags);
        
        } catch (...) {
            _reset();
            throw;
        }
    }
    
    Mmap(const std::filesystem::path& path, int flags=MAP_PRIVATE) {
        try {
            int fd = open(path.c_str(), O_RDWR);
            if (fd < 0) throw Toastbox::RuntimeError("open failed: %s", strerror(errno));
            _init(fd, flags);
        
        } catch (...) {
            _reset();
            throw;
        }
    }
    
    // Copy constructor: not allowed
    Mmap(const Mmap& x) = delete;
    // Move constructor: use move assignment operator
    Mmap(Mmap&& x) { *this = std::move(x); }
    // Move assignment operator
    Mmap& operator=(Mmap&& x) {
        _reset();
        _state = std::move(x._state);
        x._state = {};
        return *this;
    }
    
    ~Mmap() {
        _reset();
    }
    
    void sync() {
        if (!_state.fd) throw Toastbox::RuntimeError("invalid state");
        int ir = msync(_state.data, _state.len, MS_SYNC);
        if (ir) throw Toastbox::RuntimeError("msync failed: %s", strerror(errno));
    }
    
//    template <typename T=uint8_t>
//    T* data(size_t off=0) { return (T*)_state.data; }
    
//    template <typename T=uint8_t>
//    const T& data(size_t off=0) const {
//        if (off>_state.len || (_state.len-off)<sizeof(T)) {
//            const uintmax_t validStart = 0;
//            const uintmax_t validEnd = _state.len-1;
//            const uintmax_t accessStart = off;
//            const uintmax_t accessEnd = off+sizeof(T)-1;
//            throw Toastbox::RuntimeError("access beyond valid region (valid: [0x%jx,0x%jx], accessed: [0x%jx,0x%jx])",
//                validStart, validEnd,
//                accessStart, accessEnd
//            );
//        }
//        return *(const T*)(_state.data+off);
//    }
    
    template <typename T=uint8_t>
    const T* data(size_t off=0) const {
        if (off>_state.len || (_state.len-off)<sizeof(T)) {
            const uintmax_t validStart = 0;
            const uintmax_t validEnd = _state.len-1;
            const uintmax_t accessStart = off;
            const uintmax_t accessEnd = off+sizeof(T)-1;
            throw Toastbox::RuntimeError("access beyond valid region (valid: [0x%jx,0x%jx], accessed: [0x%jx,0x%jx])",
                validStart, validEnd,
                accessStart, accessEnd
            );
        }
        return (const T*)(_state.data+off);
    }
    
    template <typename T=uint8_t>
    size_t len() const { return _state.len/sizeof(T); }
    
private:
    void _init(FileDescriptor&& fd, int flags) {
        _state.fd = std::move(fd);
        
        struct stat st;
        int ir = fstat(_state.fd, &st);
        if (ir) throw Toastbox::RuntimeError("fstat failed: %s", strerror(errno));
        _state.len = st.st_size;
        
        void* data = mmap(nullptr, st.st_size, PROT_READ|PROT_WRITE, flags, _state.fd, 0);
        if (data == MAP_FAILED) throw Toastbox::RuntimeError("mmap failed: %s", strerror(errno));
        _state.data = (uint8_t*)data;
    }
    
    void _reset() {
        if (_state.data) {
            munmap((void*)_state.data, _state.len);
        }
        
        _state = {};
    }
    
    struct {
        FileDescriptor fd;
        uint8_t* data = nullptr;
        size_t len = 0;
    } _state = {};
};

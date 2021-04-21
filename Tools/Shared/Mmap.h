#pragma once
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>
#include <stdexcept>
#include <string>
#include <filesystem>
#include <unistd.h>

template <typename T=uint8_t>
class Mmap {
public:
    Mmap () {}
    Mmap(const std::filesystem::path& path) {
        try {
            _state.fd = open(path.c_str(), O_RDONLY);
            if (_state.fd < 0) throw std::runtime_error(std::string("open failed: ") + strerror(errno));
            
            struct stat st;
            int ir = fstat(_state.fd, &st);
            if (ir) throw std::runtime_error(std::string("fstat failed: ") + strerror(errno));
            _state.len = st.st_size/sizeof(T);
            
            void* data = mmap(nullptr, st.st_size, PROT_READ|PROT_WRITE, MAP_PRIVATE, _state.fd, 0);
            if (data == MAP_FAILED) throw std::runtime_error(std::string("mmap failed: ") + strerror(errno));
            _state.data = (T*)data;
        
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
        _state = x._state;
        x._state = {};
        return *this;
    }
    
    ~Mmap() {
        _reset();
    }
    
    T* data() { return _state.data; }
    const T* data() const { return _state.data; }
    // The number of T elements in `data`
    size_t len() const { return _state.len; }
    
private:
    void _reset() {
        if (_state.data) {
            munmap((void*)_state.data, _state.len);
            _state.data = nullptr;
        }
        
        if (_state.fd >= 0) {
            close(_state.fd);
            _state.fd = -1;
        }
    }
    
    struct {
        int fd = -1;
        T* data = nullptr;
        size_t len = 0;
    } _state;
};

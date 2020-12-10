#pragma once
#include <sys/stat.h>
#include <sys/mman.h>
#include <stdexcept>
#include <string>

class Mmap {
public:
    Mmap () {}
    Mmap(const char* path) {
        try {
            _fd = open(path, O_RDONLY);
            if (_fd < 0) throw std::runtime_error(std::string("open failed: ") + strerror(errno));
            
            struct stat st;
            int ir = fstat(_fd, &st);
            if (ir) throw std::runtime_error(std::string("fstat failed: ") + strerror(errno));
            _len = st.st_size;
            
            const void* data = mmap(nullptr, _len, PROT_READ, MAP_PRIVATE, _fd, 0);
            if (data == MAP_FAILED) throw std::runtime_error(std::string("mmap failed: ") + strerror(errno));
            _data = data;
        
        } catch (...) {
            _reset();
            throw;
        }
    }
    
    ~Mmap() {
        _reset();
    }
    
    const void* data() const {
        return _data;
    }
    
    size_t len() {
        return _len;
    }
    
private:
    void _reset() {
        if (_data) {
            munmap((void*)_data, _len);
            _data = nullptr;
        }
        
        if (_fd >= 0) {
            close(_fd);
            _fd = -1;
        }
    }
    
    int _fd = -1;
    const void* _data = nullptr;
    size_t _len = 0;
};

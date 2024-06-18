#pragma once

template<typename T>
class PixelSampler {
public:
    PixelSampler(size_t w, size_t h, T* px) : _w(w), _h(h), _px(px) {}
    
    template<typename Pt>
    T px(Pt x, Pt y) const {
        x = std::clamp(x, (Pt)0, (Pt)_w-1);
        y = std::clamp(y, (Pt)0, (Pt)_h-1);
        const size_t idx = (y*_w)+x;
        return _px[idx];
    }
    
private:
    const size_t _w = 0;
    const size_t _h = 0;
    const T* _px = nullptr;
};

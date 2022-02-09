#pragma once

namespace MDCTools {

template <typename T>
class Vendor : public std::enable_shared_from_this<Vendor<T>> {
private:
    using _Super = std::enable_shared_from_this<Vendor<T>>;
    
    class Vended {
    public:
        const T* operator->() const { return &_vendor->_t; }
        T* operator->() { return &_vendor->_t; }
        const T& operator*() const { return _vendor->_t; }
        T& operator*() { return _vendor->_t; }
        
    private:
        Vended(std::shared_ptr<Vendor<T>> vendor) : _vendor(vendor), _lock(_vendor->_lock) {}
        Vended(const Vended&) = delete;
        Vended(Vended&&)      = delete;
        
        std::shared_ptr<Vendor<T>> _vendor;
        std::unique_lock<std::mutex> _lock;
        
        friend class Vendor;
    };
    
    std::mutex _lock;
    T _t;
    
    friend class Vended;
    
public:
//    template<typename... Args>
//    static std::shared_ptr<Vendor<T>> MakeShared(Args&&... args) {
//        return std::make_shared<Vendor<T>>(args...);
//    }
    
    template<typename... Args>
    Vendor(Args&&... args) : _t(std::forward<Args>(args)...) {}
    
    Vended vend() { return Vended(_getShared()); }
    
    const Vended operator->() const { return Vended(_getShared()); }
    Vended operator->() { return Vended(_getShared()); }
    
private:
    std::shared_ptr<Vendor<T>> _getShared() {
        return _Super::shared_from_this();
    }
//    const T& operator*() const { return _vendor->_t; }
//    T& operator*() { return _vendor->_t; }
};

} // namespace MDCTools

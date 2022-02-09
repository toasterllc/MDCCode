#pragma once

namespace MDCTools {

// Vendor: provides a convenient locking and smart-pointer mechanism
// For example:
//   auto vendor = std::make_shared<Vendor<Obj>>();
//   {
//     auto obj = vendor->vend();
//     obj->func();
//   }
// Other threads are prevented from acquiring the vended object until the
// above scope has ended. Further, within that scope, the vended object
// `obj` is guaranteed to be valid, even if `vendor` is destroyed.

template <typename T>
class Vendor : public std::enable_shared_from_this<Vendor<T>> {
private:
    class Vended {
    public:
        T* operator->() { return &_vendor->_t; }
        const T* operator->() const { return &_vendor->_t; }
        T& operator*() { return _vendor->_t; }
        const T& operator*() const { return _vendor->_t; }
        operator T&() { return _vendor->_t; }
        operator const T&() const { return _vendor->_t; }
        
    private:
        Vended(std::shared_ptr<Vendor<T>> vendor) : _vendor(vendor), _lock(_vendor->_lock) {}
        Vended(const Vended&) = delete;
        Vended(Vended&&)      = delete;
        
        std::shared_ptr<Vendor<T>> _vendor;
        std::unique_lock<std::mutex> _lock;
        
        friend class Vendor;
    };
    
    std::shared_ptr<Vendor<T>> _getShared() {
        using super = std::enable_shared_from_this<Vendor<T>>;
        return super::shared_from_this();
    }
    
    std::mutex _lock;
    T _t;
    
    friend class Vended;
    
public:
    template<typename... Args>
    Vendor(Args&&... args) : _t(std::forward<Args>(args)...) {}
    
    Vended vend() { return Vended(_getShared()); }
    
    const Vended operator->() const { return Vended(_getShared()); }
    Vended operator->() { return Vended(_getShared()); }
};

} // namespace MDCTools

#pragma once
#include <mutex>

namespace MDCTools {

template <typename T>
class Lockable : public T, public std::mutex {
public:
    using T::T;
    Lockable(const T& t) : T(t) {}
    Lockable(T&& t) : T(std::move(t)) {}
};

} // namespace MDCTools

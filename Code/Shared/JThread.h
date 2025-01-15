#pragma once

// JThread: convenience to automatically join() the thread upon instance destruction
struct JThread : std::thread {
    using std::thread::thread;
    
    // Move constructor
    JThread(JThread&& x) { set(std::move(x)); }
    // Move assignment operator
    JThread& operator=(JThread&& x) { set(std::move(x)); return *this; }
    
    ~JThread() {
        if (joinable()) join();
    }
    
    void set(JThread&& x) {
        if (joinable()) join();
        std::thread::operator=(std::move(x));
    }
};

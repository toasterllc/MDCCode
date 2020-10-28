class StartupBase {
public:
    void run();

protected:
    void runInit();
};

// `Startup` is called by VectorTable.s,
// and must be implemented by the client
extern "C" void Startup();

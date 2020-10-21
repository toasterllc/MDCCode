struct STLoaderCmd {
    enum class Op : uint8_t {
        None,
        LEDSet,
        WriteData,
        Reset,
    };
    
    Op op;
    union {
        struct {
            uint8_t idx;
            uint8_t on;
        } ledSet;
        
        struct {
            uint32_t addr;
        } writeData;
        
        struct {
            uint32_t vectorTableAddr;
        } reset;
    } arg;
} __attribute__((packed));

static_assert(sizeof(STLoaderCmd)==5, "STLoaderCmd: invalid size");

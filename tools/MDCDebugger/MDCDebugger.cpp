#include <stdio.h>
#include <assert.h>
#include <vector>
#include <queue>
#include <algorithm>
#include <unistd.h>
#include <libftdi1/ftdi.h>

class MSP430JTAG {
public:
    enum Pin : uint8_t {
        CLK     = 0x1,
        CS      = 0x2,
        DI      = 0x3,
        DO      = 0x4,
    };
    
    struct PinConfig {
        uint8_t pin = 0;
        uint8_t dir = 0;
        uint8_t val = 0;
    };
    
    MSP430JTAG() {
        int ir = ftdi_init(&_ftdi);
        assert(!ir);
        
        ir = ftdi_set_interface(&_ftdi, INTERFACE_A);
        assert(!ir);
        
        struct ftdi_device_list* devices = nullptr;
        int devicesCount = ftdi_usb_find_all(&_ftdi, &devices, 0x403, 0x6014);
        assert(devicesCount == 1);
        
        // Open FTDI USB device
        ir = ftdi_usb_open_dev(&_ftdi, devices[0].dev);
        assert(!ir);
        
        // Reset USB device
        ir = ftdi_usb_reset(&_ftdi);
        assert(!ir);
        
        // // Clear incoming data
        // for (;;) {
        //     uint8_t buf[16];
        //     ir = ftdi_read_data(&_ftdi, buf, sizeof(buf));
        //     assert(ir >= 0);
        //     if (ir == 0) {
        //         break;
        //     }
        // }
        
        // Set chunk sizes to 64K
        ir = ftdi_read_data_set_chunksize(&_ftdi, 65536);
        assert(!ir);
        
        ir = ftdi_write_data_set_chunksize(&_ftdi, 65536);
        assert(!ir);
        
        // Disable event/error characters
        ir = ftdi_set_event_char(&_ftdi, 0, 0);
        assert(!ir);
        
        ir = ftdi_set_event_char(&_ftdi, 0, 0);
        assert(!ir);
        
        // TODO: ftStatus |= FT_SetTimeouts(ftHandle, 0, 5000);
        
        // Set buffer interval ("The FTDI chip keeps data in the internal buffer
        // for a specific amount of time if the buffer is not full yet to decrease
        // load on the usb bus.")
        ir = ftdi_set_latency_timer(&_ftdi, 16);
        assert(!ir);
        
        // Set FTDI mode to MPSSE
        ir = ftdi_set_bitmode(&_ftdi, 0xFF, 0);
        assert(!ir);
        
        // Set FTDI mode to MPSSE
        ir = ftdi_set_bitmode(&_ftdi, 0xFF, BITMODE_MPSSE);
        assert(!ir);
        
        // Flush the read buffer
        for (;;) {
            uint8_t tmp[128];
            int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
            printf("read %d bytes\n", ir);
            assert(ir >= 0);
            if (!ir) break;
        }
        
        // Use 60MHz master clock, disable adaptive clocking, disable three-phase clocking, disable loopback
        {
            uint8_t cmd[] = {0x8A, 0x97, 0x8D, 0x85};
            ir = ftdi_write_data(&_ftdi, cmd, sizeof(cmd));
            assert(ir == sizeof(cmd));
        }
        
        // Set TCK frequency to 1MHz
        {
            uint8_t cmd[] = {0x86, 0x1D, 0x00};
            ir = ftdi_write_data(&_ftdi, cmd, sizeof(cmd));
            assert(ir == sizeof(cmd));
        }
        
        // Synchronize with FTDI by sending a bad command and ensuring we get the expected error
        {
//            for (;;) {
//                auto tmp = _readData(1);
//                printf("read %zu bytes\n", tmp.size());
//            }
            
            
            
            uint8_t cmd[] = {0xAA};
            struct ftdi_transfer_control* xfer = ftdi_write_data_submit(&_ftdi, cmd, sizeof(cmd));
            assert(xfer);
            
//            ir = ftdi_write_data(&_ftdi, cmd, sizeof(cmd));
            printf("ftdi_write_data: %d\n", ir);
//            assert(ir == sizeof(cmd));
            
            // Flush the read buffer
            for (;;) {
                uint8_t tmp[128];
                int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
                printf("0xAA response: read %d bytes\n", ir);
                assert(ir >= 0);
//                if (!ir) break;
            }
            
            
            auto resp = _readData(2);
            assert(resp[0]==0xFA && resp[1]==0xAA);
        }
    }
    
    ~MSP430JTAG() {
        int ir = ftdi_usb_close(&_ftdi);
        assert(!ir);
        
        ftdi_deinit(&_ftdi);
    }
    
    void enqueue(const std::vector<uint8_t> cmd) {
        _cmds.insert(_cmds.end(), cmd.begin(), cmd.end());
    }
    
    void setPins(std::vector<PinConfig> configs) {
        for (const PinConfig& c : configs) {
            _pinDirs = (_pinDirs&(~c.pin))|(c.dir ? c.pin : 0);
            _pinVals = (_pinVals&(~c.pin))|(c.val ? c.pin : 0);
        }
        // printf("_pinVals:0x%x _pinDirs:0x%x\n", _pinVals, _pinDirs);
        enqueue({0x80, _pinVals, _pinDirs});
    }
    
    // Reset MSP430 JTAG controller back to Run-Test/Idle
    void resetJTAG() {
        setPins({   {.pin=Pin::TCK, .dir=1, .val=1},
                    {.pin=Pin::TMS, .dir=1, .val=1}});
        clocks(6); // "minimum of six TCK clocks be sent to the target device while TMS is high"
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}});
        clocks(1); // "[set] TMS low for at least one TCK clock"
    }
    
    void clocks(uint8_t n) {
        uint8_t bytes = n/8;
        uint8_t bits = n%8;
        if (bytes) enqueue({0x8F, (uint8_t)(bytes-1)});
        if (bits) enqueue({0x8E, (uint8_t)(bits-1)});
    }
    
    enum class ShiftDir {
        Out,    // Out of host (into target device)
        InOut,  // Into host + out of host (out of target device + into target device)
    };
    
    void shiftIR(uint8_t ir, ShiftDir dir=ShiftDir::Out) {
        _enterShiftIRState();
        _shift({ir}, dir);
    }
    
    void shiftDR(uint16_t dr, ShiftDir dir=ShiftDir::Out) {
        _enterShiftDRState();
        _shift({(uint8_t)((dr&0xFF00)>>8), (uint8_t)(dr&0xFF)}, dir);
    }
    
    void enableJTAG() {
        // ## Reset our pin state, making sure that we exit test mode by holding TEST=0 for >100us
        setPins({
            {.pin=Pin::TCK,     .dir=1,     .val=0},
            {.pin=Pin::TDI,     .dir=1,     .val=0},
            {.pin=Pin::TDO,     .dir=0,     .val=0},
            {.pin=Pin::TMS,     .dir=1,     .val=0},
            {.pin=Pin::TEST,    .dir=1,     .val=0},
            {.pin=Pin::RST_,    .dir=1,     .val=1},
        });
        execute();
        usleep(100);
        
        // ## Reset the CPU so its starts from a known state
        setPins({{.pin=Pin::RST_, .dir=1, .val=0}});
        setPins({{.pin=Pin::RST_, .dir=1, .val=1}});
        
        // ## Enable 4-wire JTAG
        // Assert TEST
        // TEST: 0->1
        // RST_: 1->0
        // RST_ is latched when TEST is asserted, so RST_ will be latched low,
        // therefore the chip won't be in reset
        setPins({{.pin=Pin::TEST, .dir=1, .val=1}});
        
        // Toggle TEST while RST_ is low to enable 4-wire JTAG:
        //   "The 4-wire JTAG interface access is enabled by pulling
        //   the RST_ line low and then applying a clock on TEST.
        //   Exit the 4-wire JTAG mode by holding the TEST low for
        //   more than 100 μs."
        setPins({{.pin=Pin::RST_, .dir=1, .val=0}});
        setPins({{.pin=Pin::TEST, .dir=1, .val=0}});
        setPins({{.pin=Pin::TEST, .dir=1, .val=1}});
        
        // ## Reset JTAG state machine
        _resetJTAGStateMachine();
        // JTAG State: Run-Test/Idle
        
        // ## Fuse check: toggle TMS without toggling TCK
        setPins({{.pin=Pin::TMS, .dir=1, .val=1}});
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}});
        execute(); // "the low phase of the two TMS pulses should last a minimum of 5 μs."
        usleep(5);
        
        setPins({{.pin=Pin::TMS, .dir=1, .val=1}});
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}});
        execute(); // "the low phase of the two TMS pulses should last a minimum of 5 μs."
        usleep(5);
        
        // ## Take the CPU under JTAG control
        shiftIR(0xC8);
        shiftDR(0x2401);
        shiftIR(0x28, ShiftDir::InOut);
        auto jtagID = readData(1);
        assert(jtagID[0] == 0x89);
        printf("jtag ID: 0x%x\n", jtagID[0]);
        
        bool ok = false;
        for (int i=0; i<50; i++) {
            shiftDR(0x0000, ShiftDir::InOut);
            auto tmp = readData(2);
            if (tmp[0] & 0x2) {
                ok = true;
                break;
            }
        }
        
        assert(ok);
        printf("CPU under JTAG control\n");
    }
    
    void _resetJTAGStateMachine() {
        // ## Reset JTAG
        // Go to the Test-Logic-Reset state via 6 clocks with TMS=1
        setPins({{.pin=Pin::TMS, .dir=1, .val=1}});
        clocks(6);
        
        // JTAG State: Test-Logic-Reset
        // Go to the Run-Test/Idle state via 1 clock with TMS=0
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}});
        clocks(1);
    }
    
    void _shift(const std::vector<uint8_t> data, ShiftDir dir=ShiftDir::Out) {
        assert(!data.empty());
        
        uint8_t opcodeBytes = 0;
        uint8_t opcodeBits = 0;
        switch (dir) {
        case ShiftDir::Out:     opcodeBytes = 0x11; opcodeBits = 0x13; break;
        case ShiftDir::InOut:   opcodeBytes = 0x31; opcodeBits = 0x33; break;
        }
        
        // JTAG State: Shift-DR / Shift-IR
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}}); // TMS=0
        
        if (data.size() > 1) {
            std::vector<uint8_t> cmd = {opcodeBytes, (uint8_t)((data.size()-2)&0xFF), (uint8_t)(((data.size()-2)&0xFF00)>>8)};
            cmd.insert(cmd.end(), data.begin(), data.end()-1);
            enqueue(cmd);
            
            if (dir == ShiftDir::InOut) {
                for (size_t i=0; i<data.size()-1; i++) _readMask.push(true);
            }
        }
        
        enqueue({opcodeBits, 0x06, data.back()}); // Send high 7 bits of last byte
        if (dir == ShiftDir::InOut) _readMask.push(false);
        
        setPins({{.pin=Pin::TMS, .dir=1, .val=1}}); // TMS=1
        enqueue({opcodeBits, 0x00, (uint8_t)(data.back()<<7)}); // Send last bit of last byte
        if (dir == ShiftDir::InOut) _readMask.push(true);
        
        // JTAG State: Exit1-DR / Exit1-IR
        clocks(1);
        
        // JTAG State: Update-DR / Update-IR
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}}); // TMS=0
        clocks(1);
        
        // JTAG State: Run-Test/Idle
    }
    
    void _enterShiftIRState() {
        // JTAG State: Run-Test/Idle
        setPins({{.pin=Pin::TMS, .dir=1, .val=1}});
        clocks(2);

        // JTAG State: Select IR-Scan
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}});
        clocks(2);

        // JTAG State: Shift-IR
    }
    
    void _enterShiftDRState() {
        // JTAG State: Run-Test/Idle
        setPins({{.pin=Pin::TMS, .dir=1, .val=1}});
        clocks(1);

        // JTAG State: Select-DR-Scan
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}});
        clocks(2);

        // JTAG State: Shift-DR
    }
    
    std::vector<uint8_t> readData(size_t n) {
        execute();
        
//        printf("_readMask.size(): 0x%zx\n", _readMask.size());
        std::vector<uint8_t> result;
        while (result.size() < n) {
            // Verify that there are more bytes expected
            assert(!_readMask.empty());
            
            std::vector<uint8_t> data = _readData(n-result.size());
//            printf("data.size(): 0x%zx\n", data.size());
            
            // Remove bytes from `data` that are masked
            for (const uint8_t& d : data) {
                if (_readMask.front()) result.push_back(d);
                _readMask.pop();
            }
        }
//        printf("result.size(): 0x%zx\n", result.size());
        return result;
    }
    
    std::vector<uint8_t> _readData(size_t n) {
        std::vector<uint8_t> result(n);
        size_t len = 0;
        while (len < n) {
            const size_t readLen = n-len;
            int ir = ftdi_read_data(&_ftdi, result.data()+len, (int)readLen);
            // printf("ftdi_read_data returned: 0x%x\n", ir);
            assert(ir>=0 && (size_t)ir<=readLen);
            len += ir;
        }
        return result;
    }
    
    // void setPins(uint8_t pins, uint8_t dirs, uint8_t vals) {
    //     _pinDirs = (_pinDirs&(~pins))|dirs;
    //     savedVals = (savedVals&(~pins))|vals;
    //     printf("savedVals:0x%x _pinDirs:0x%x\n", savedVals, _pinDirs);
    //
    //     uint8_t cmd[] = {0x80, savedVals, _pinDirs};
    //     enqueue(cmd, sizeof(cmd));
    //
    //     return ftdi_write_data(ftdi, cmd, sizeof(cmd));
    //
    //
    //     _cmds.insert(_cmds.end(), cmds, cmds+len);
    // }
    
    void execute() {
        int ir = ftdi_write_data(&_ftdi, _cmds.data(), (int)_cmds.size());
        assert(ir>=0 && (size_t)ir==_cmds.size());
        _cmds.clear();
    }
    
    
    
    
    void jtag_release_cpu()
    {
        jtag_tclk_clr();

        /* clear the HALT_JTAG bit */
        jtag_ir_shift(IR_CNTRL_SIG_16BIT);
        jtag_dr_shift_16(0x2401);
        jtag_ir_shift(IR_ADDR_CAPTURE);
        jtag_tclk_set();
    }
    
    
    /* Set the CPU into a controlled stop state */
    void jtag_halt_cpu()
    {
        /* Set CPU into instruction fetch mode */
        jtag_set_instruction_fetch();

        /* Set device into JTAG mode + read */
        jtag_ir_shift(IR_CNTRL_SIG_16BIT);
        jtag_dr_shift_16(0x2401);

        /* Send JMP $ instruction to keep CPU from changing the state */
        jtag_ir_shift(IR_DATA_16BIT);
        jtag_dr_shift_16(0x3FFF);
        jtag_tclk_set();
        jtag_tclk_clr();

        /* Set JTAG_HALT bit */
        jtag_ir_shift(IR_CNTRL_SIG_16BIT);
        jtag_dr_shift_16(0x2409);
        jtag_tclk_set();
    }
    
    int jtag_set_instruction_fetch()
    {
        unsigned int loop_counter;

        jtag_ir_shift(IR_CNTRL_SIG_CAPTURE);
        /* Wait until CPU is in instruction fetch state
         * timeout after limited attempts
         */
        for (loop_counter = 50; loop_counter > 0; loop_counter--) {
            if ((jtag_dr_shift_16(0x0000) & 0x0080) == 0x0080)
                return 1;

            jtag_tclk_clr(); /* The TCLK pulse befor jtag_dr_shift_16 leads to   */
            jtag_tclk_set(); /* problems at MEM_QUICK_READ, it's from SLAU265 */
        }

        printf("jtag_set_instruction_fetch: failed\n");

        return 0;
    }
    
    
    unsigned int jtag_execute_puc()
    {
        unsigned int jtag_id;

        jtag_ir_shift(IR_CNTRL_SIG_16BIT);

        /* Apply and remove reset */
        jtag_dr_shift_16(0x2C01);
        jtag_dr_shift_16(0x2401);
        jtag_tclk_clr();
        jtag_tclk_set();
        jtag_tclk_clr();
        jtag_tclk_set();
        jtag_tclk_clr();
        jtag_tclk_set();

        /* Read jtag id */
        jtag_id = jtag_ir_shift(IR_ADDR_CAPTURE);

        /* Disable watchdog on target device */
        jtag_write_mem(16, 0x0120, 0x5A80);

        return jtag_id;
    }
    
    void jtag_write_mem(unsigned int format, address_t address, uint16_t data)
    {
        jtag_halt_cpu();
        jtag_tclk_clr();
        jtag_ir_shift(IR_CNTRL_SIG_16BIT);

        if (format == 16)
            /* Set word write */
            jtag_dr_shift_16(0x2408);
        else
            /* Set byte write */
            jtag_dr_shift_16(0x2418);

        jtag_ir_shift(IR_ADDR_16BIT);

        /* Set addr */
        jtag_dr_shift_16(address);
        jtag_ir_shift(IR_DATA_TO_ADDR);

        /* Shift in 16 bits */
        jtag_dr_shift_16(data);
        jtag_tclk_set();
        jtag_release_cpu();
    }
    
    
    
    unsigned int jtag_init()
    {
        unsigned int jtag_id;

        jtag_rst_clr();
        // p->f->jtdev_power_on();
        jtag_tdi_set();
        jtag_tms_set();
        jtag_tck_set();
        jtag_tclk_set();

        jtag_rst_set();
        jtag_tst_clr();

        jtag_tst_set();
        jtag_rst_clr();
        jtag_tst_clr();

        jtag_tst_set();

        // p->f->jtdev_connect();
        jtag_rst_set();
        jtag_reset_tap();

        /* Check fuse */
        if (jtag_is_fuse_blown()) {
            printf("jtag_init: fuse is blown\n");
            // p->failed = 1;
            return 0;
        }

        /* Set device into JTAG mode */
        jtag_id = jtag_get_device();
        printf("jtag_id: 0x%x\n", jtag_id);
        if (jtag_id == 0) {
            printf("jtag_init: invalid jtag_id: 0x%02x\n", jtag_id);
            // p->failed = 1;
            return 0;
        }

        /* Perform PUC, includes target watchdog disable */
        if (jtag_execute_puc() != jtag_id) {
            printf("jtag_init: PUC failed\n");
            // p->failed = 1;
            return 0;
        }

        return jtag_id;
    }
    
    void jtag_reset_tap()
    {
        int loop_counter;

        jtag_tms_set();
        jtag_tck_set();

        /* Perform fuse check */
        jtag_tms_clr();
        jtag_tms_set();
        jtag_tms_clr();
        jtag_tms_set();

        /* Reset JTAG state machine */
        for (loop_counter = 6; loop_counter > 0; loop_counter--) {
            jtag_tck_clr();
            jtag_tck_set();

            // if (p->failed)
            //     return;
        }

        /* Set JTAG state machine to Run-Test/IDLE */
        jtag_tck_clr();
        jtag_tms_clr();
        jtag_tck_set();
    }
    
    int jtag_is_fuse_blown()
    {
        unsigned int loop_counter;

        /* First trial could be wrong */
        for (loop_counter = 3; loop_counter > 0; loop_counter--) {
            jtag_ir_shift(IR_CNTRL_SIG_CAPTURE);
            if (jtag_dr_shift_16(0xAAAA) == 0x5555)
                /* Fuse is blown */
                return 1;
        }

        /* Fuse is not blown */
        return 0;
    }
    
    unsigned int jtag_get_device()
    {
        unsigned int jtag_id = 0;
        unsigned int loop_counter;

        /* Set device into JTAG mode + read */
        jtag_ir_shift(IR_CNTRL_SIG_16BIT);
        jtag_dr_shift_16(0x2401);

        /* Wait until CPU is synchronized,
         * timeout after a limited number of attempts
         */
        jtag_id = jtag_ir_shift(IR_CNTRL_SIG_CAPTURE);
        for ( loop_counter = 50; loop_counter > 0; loop_counter--) {
            if ( (jtag_dr_shift_16(0x0000) & 0x0200) == 0x0200 ) {
                break;
            }
        }
        printf("jtag_get_device: jtag_id: 0x%x\n", jtag_id);

        if (loop_counter == 0) {
            printf("jtag_get_device: timed out\n");
            // p->failed = 1;
            /* timeout reached */
            return 0;
        }
        
        printf("jtag_led_green_on\n");
        return jtag_id;
    }
    
    unsigned int jtag_dr_shift_16(unsigned int data)
    {
        /* JTAG state = Run-Test/Idle */
        jtag_tms_set();
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Select DR-Scan */
        jtag_tms_clr();
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Capture-DR */
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Shift-DR, Shift in TDI (16-bit) */
        return jtag_shift(16, data);

        /* JTAG state = Run-Test/Idle */
    }
    
    
    
    void jtag_tck_clr() {
        setPins({{.pin=Pin::TCK, .dir=1, .val=0}});
        execute();
        // usleep(100);
    }
    
    void jtag_tck_set() {
        setPins({{.pin=Pin::TCK, .dir=1, .val=1}});
        execute();
        // usleep(100);
    }
    
    void jtag_tms_clr() {
        setPins({{.pin=Pin::TMS, .dir=1, .val=0}});
        execute();
        // usleep(100);
    }
    
    void jtag_tms_set() {
        setPins({{.pin=Pin::TMS, .dir=1, .val=1}});
        execute();
        // usleep(100);
    }
    
    void jtag_tdi_clr() {
        setPins({{.pin=Pin::TDI, .dir=1, .val=0}});
        execute();
        // usleep(100);
    }
    
    void jtag_tdi_set() {
        setPins({{.pin=Pin::TDI, .dir=1, .val=1}});
        execute();
        // usleep(100);
    }
    
    void jtag_tclk_clr() {
        // TCLK is just TDI
        jtag_tdi_clr();
    }
    
    void jtag_tclk_set() {
        // TCLK is just TDI
        jtag_tdi_set();
    }
    
    void jtag_rst_clr() {
        setPins({{.pin=Pin::RST_, .dir=1, .val=0}});
        execute();
        // usleep(100);
    }
    
    void jtag_rst_set() {
        setPins({{.pin=Pin::RST_, .dir=1, .val=1}});
        execute();
        // usleep(100);
    }
    
    void jtag_tst_clr() {
        setPins({{.pin=Pin::TEST, .dir=1, .val=0}});
        execute();
        // usleep(100);
    }
    
    void jtag_tst_set() {
        setPins({{.pin=Pin::TEST, .dir=1, .val=1}});
        execute();
        // usleep(100);
    }
    
    uint8_t jtag_tclk_get() {
        // TCLK is just TDI
        // usleep(100);
        uint8_t pins = 0;
        int ir = ftdi_read_pins(&_ftdi, &pins);
        assert(!ir);
        return (pins>>1)&0x1;
    }
    
    uint8_t jtag_tdo_get() {
        // usleep(100);
        uint8_t pins = 0;
        int ir = ftdi_read_pins(&_ftdi, &pins);
        assert(!ir);
        return (pins>>2)&0x1;
    }
    
    uint8_t jtag_tck_get() {
        // usleep(100);
        uint8_t pins = 0;
        int ir = ftdi_read_pins(&_ftdi, &pins);
        assert(!ir);
        return (pins>>0)&0x1;
    }
    
    
    
    unsigned int jtag_ir_shift(unsigned int instruction) {
        /* JTAG state = Run-Test/Idle */
        jtag_tms_set();
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Select DR-Scan */
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Select IR-Scan */
        jtag_tms_clr();
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Capture-IR */
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Shift-IR, Shift in TDI (8-bit) */
        return jtag_shift(8, instruction);

        /* JTAG state = Run-Test/Idle */
    }

    unsigned int jtag_shift(unsigned char num_bits, unsigned int data_out) {
        unsigned int data_in;
        unsigned int mask;
        unsigned int tclk_save;

        tclk_save = jtag_tclk_get();

        data_in = 0;
        for (mask = 0x0001U << (num_bits - 1); mask != 0; mask >>= 1) {
            if ((data_out & mask) != 0)
                jtag_tdi_set();
            else
                jtag_tdi_clr();

            if (mask == 1)
                jtag_tms_set();

            jtag_tck_clr();
            jtag_tck_set();

            if (jtag_tdo_get() == 1)
                data_in |= mask;
        }

        if (tclk_save) jtag_tclk_set();
        else jtag_tclk_clr();

        /* Set JTAG state back to Run-Test/Idle */
        jtag_tclk_prep();

        // printf("jtag_shift returning 0x%x\n", data_in);
        return data_in;
    }
    
    void jtag_tclk_prep()
    {
        /* JTAG state = Exit-DR */
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Update-DR */
        jtag_tms_clr();
        jtag_tck_clr();
        jtag_tck_set();

        /* JTAG state = Run-Test/Idle */
    }
    
    
private:
    struct ftdi_context _ftdi;
    std::vector<uint8_t> _cmds;
    uint8_t _pinDirs = 0;
    uint8_t _pinVals = 0;
    std::queue<bool> _readMask;
};

int main() {
    using Pin = MSP430JTAG::Pin;
    using ShiftDir = MSP430JTAG::ShiftDir;
    
    MSP430JTAG device;
    device.enableJTAG();
    
    
//    // Debugging:
//    // Reset MSP430
//    {
//        device.setPins({
//            {.pin=Pin::TCK,     .dir=1,     .val=0},
//            {.pin=Pin::TDI,     .dir=1,     .val=0},
//            {.pin=Pin::TDO,     .dir=0,     .val=0},
//            {.pin=Pin::TMS,     .dir=1,     .val=0},
//            {.pin=Pin::TEST,    .dir=1,     .val=0},
//            {.pin=Pin::RST_,    .dir=1,     .val=1},
//        });
//        device.execute();
//        usleep(100);
//
//        // ## Reset the CPU so its starts from a known state
//        device.setPins({{.pin=Pin::RST_, .dir=1, .val=0}});
//        device.setPins({{.pin=Pin::RST_, .dir=1, .val=1}});
//        device.execute();
//    }
    
    
    
    
//    // Debugging:
//    // Strobe TDI 40 times at 350kHz
//    // The number of dummy GPIO assignments was determined empirically to result in 350kHz
//    for (int ii=0; ii<0x10000; ii++) {
//        for (int i=0; i<40; i++) {
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=1}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=1}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=1}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=1}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=1}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=1}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=1}});
//
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=0}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=0}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=0}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=0}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=0}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=0}});
//            device.setPins({{.pin=Pin::TDI, .dir=1, .val=0}});
//        }
//        device.execute();
//    }
    
    return 0;
}

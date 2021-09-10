#pragma once
#include <initializer_list>
#include "Assert.h"
#include "Channel.h"
#include "stm32f7xx.h"
#include "usbd_def.h"
#include "usbd_core.h"
//#include "usbd_ctlreq.h"
#include "usbd_desc.h"
//#include "usbd_ioreq.h"

extern "C" void ISR_OTG_HS();

template <
typename T,             // Subclass
bool DMAEn,             // Whether DMA is enabled
uint8_t... Endpoints    // List of endpoints
>
class USBBase {
public:
    static constexpr size_t MaxPacketSizeCtrl = 64;
    static constexpr size_t MaxPacketSizeBulk = 512;
    
    static constexpr uint8_t EndpointIdx(uint8_t ep)    { return ep&0xF;        }
    static constexpr bool EndpointOut(uint8_t ep)       { return !(ep&0x80);    }
    static constexpr bool EndpointIn(uint8_t ep)        { return  (ep&0x80);    }
    
    static constexpr size_t EndpointCountOut() {
        size_t count = 0;
        for (uint8_t ep : {Endpoints...}) count += EndpointOut(ep);
        return count;
    }
    
    static constexpr size_t EndpointCountIn() {
        size_t count = 0;
        for (uint8_t ep : {Endpoints...}) count += EndpointIn(ep);
        return count;
    }
    
    static constexpr size_t MaxPacketSizeIn() {
        // Don't have IN endpoints: MPS=control transfer MPS (64)
        // Do have IN endpoints: MPS=bulk transfer MPS (512, the only value that the spec allows for HS bulk endpoints)
        return !EndpointCountIn() ? MaxPacketSizeCtrl : MaxPacketSizeBulk;
    }
    
    static constexpr size_t MaxPacketSizeOut() {
        // Don't have OUT endpoints: MPS=control transfer MPS (64)
        // Do have OUT endpoints: MPS=bulk transfer MPS (512, the only value that the spec allows for HS bulk endpoints)
        return !EndpointCountOut() ? MaxPacketSizeCtrl : MaxPacketSizeBulk;
    }
    
    static constexpr uint32_t FIFORxSize() {
        // EndpointCountCtrl: Hardcoded because the hardware seems to assume that there's only
        // one control endpoint (EP0)
        constexpr uint8_t EndpointCountCtrl = 1;
        // Formula from STM32 Reference Manual "USB on-the-go full-speed/high-speed (OTG_FS/OTG_HS)"
        //
        //   Device RxFIFO =
        //     (5 * number of control endpoints + 8) +
        //     ((largest USB packet used / 4) + 1 for status information) +
        //     (2 * number of OUT endpoints) +
        //     (1 for Global NAK)
        //
        // We multiply the second term by 2 (unlike the formula in the reference manual) because
        // the reference manual states:
        //   "Typically, two (largest packet size / 4) + 1 spaces are recommended so that when the
        //   previous packet is being transferred to the CPU, the USB can receive the subsequent
        //   packet."
        return (
            (5*EndpointCountCtrl+8)                     +
            (2*((MaxPacketSizeOut()/4)+1))              +
            (2*(EndpointCountCtrl+EndpointCountOut()))  +
            (1)
        ) * sizeof(uint32_t);
    }
    
    // Types
    struct Event {
        enum class Type : uint8_t {
            StateChanged,
        };
        Type type;
    };
    
    enum class State : uint8_t {
        Disconnected,
        Connected,
    };
    
    // Initialization
    void init() {
        _pcd.pData = &_device;
        _pcd.Instance = USB_OTG_HS;
        _pcd.Init.dev_endpoints = 9;
        _pcd.Init.dma_enable = DMAEn;
        _pcd.Init.phy_itface = USB_OTG_HS_EMBEDDED_PHY;
        _pcd.Init.sof_enable = false;
        _pcd.Init.low_power_enable = false;
        _pcd.Init.lpm_enable = false;
        _pcd.Init.vbus_sensing_enable = false;
        _pcd.Init.use_dedicated_ep1 = false;
        _pcd.Init.use_external_vbus = false;
        
        _device.pData = &_pcd;
        
        USBD_StatusTypeDef us = USBD_Init(&_device, &HS_Desc, DEVICE_HS, this);
        Assert(us == USBD_OK);
        
        HAL_StatusTypeDef hs = HAL_PCD_Init(&_pcd);
        Assert(hs == HAL_OK);
        
#define Fwd0(name) [](USBD_HandleTypeDef* pdev) { return ((T*)pdev->pCtx)->_usbd_##name(); }
#define Fwd1(name, T0) [](USBD_HandleTypeDef* pdev, T0 t0) { return ((T*)pdev->pCtx)->_usbd_##name(t0); }
#define Fwd2(name, T0, T1) [](USBD_HandleTypeDef* pdev, T0 t0, T1 t1) { return ((T*)pdev->pCtx)->_usbd_##name(t0, t1); }
        
        static const USBD_ClassTypeDef usbClass = {
            .Init                           = Fwd1(Init, uint8_t),
            .DeInit                         = Fwd1(DeInit, uint8_t),
            .Setup                          = Fwd1(Setup, USBD_SetupReqTypedef*),
            .EP0_TxSent                     = Fwd0(EP0_TxSent),
            .EP0_RxReady                    = Fwd0(EP0_RxReady),
            .DataIn                         = Fwd1(DataIn, uint8_t),
            .DataOut                        = Fwd1(DataOut, uint8_t),
            .SOF                            = Fwd0(SOF),
            .IsoINIncomplete                = Fwd1(IsoINIncomplete, uint8_t),
            .IsoOUTIncomplete               = Fwd1(IsoOUTIncomplete, uint8_t),
            .GetHSConfigDescriptor          = Fwd1(GetHSConfigDescriptor, uint16_t*),
            .GetFSConfigDescriptor          = Fwd1(GetFSConfigDescriptor, uint16_t*),
            .GetOtherSpeedConfigDescriptor  = Fwd1(GetOtherSpeedConfigDescriptor, uint16_t*),
            .GetDeviceQualifierDescriptor   = Fwd1(GetDeviceQualifierDescriptor, uint16_t*),
            .GetUsrStrDescriptor            = Fwd2(GetUsrStrDescriptor, uint8_t, uint16_t*),
        };
        
#undef Fwd0
#undef Fwd1
#undef Fwd2
        
        us = USBD_RegisterClass(&_device, &usbClass);
        Assert(us == USBD_OK);
        
        us = USBD_Start(&_device);
        Assert(us == USBD_OK);
        
        // ## Set Rx/Tx FIFO sizes. Notes:
        //   - OTG HS FIFO RAM is 4096 bytes, and must be shared amongst all endpoints.
        //   
        //   - FIFO sizes passed to HAL_PCDEx_SetRxFiFo/HAL_PCDEx_SetTxFiFo have units of 4-byte words.
        //   
        //   - When DMA is enabled, the DMA-related FIFO registers appear to be stored at the end of the
        //     FIFO RAM, so we reserve space using `FIFOCapDMARegisters`. The ST docs are silent about
        //     the need to reserve space for these registers, but we determined that it's necessary because:
        //       
        //       - USB transfers fail when DMA is enabled and we use the entire FIFO without leaving space
        //         at the end
        //       
        //       - when we don't leave space at the end for the DMA registers, and we dump the entire 4k
        //         FIFO RAM contents [1], the RAM shows parts of our transfer data being clobbered by
        //         values that appear to pointers within the FIFO RAM (and match the sizes we choose for
        //         the Rx/Tx FIFOs)
        //       
        //       - the Silicon Labs EFM32HG uses the same/similar Synopsys USB IP, and its docs say:
        //           - "These register information are stored at the end of the FIFO RAM after the space
        //              allocated for receive and Transmit FIFO. These register space must also be taken
        //              into account when calculating the total FIFO depth of the core"
        //           
        //           - "how much RAM space must be allocated to store these registers"
        //             - "DMA mode: One location per end point direction"
        //       
        //       - we don't know the exact size to reserve for the DMA registers, but:
        //         - empircally: 64 bytes doesn't work, 128 does work
        //         - "One location per end point direction":
        //             +1 for control IN endpoint
        //             +1 for control OUT endpoint
        //             +8 IN endpoints
        //             +8 OUT endpoints
        //             = 18 locations * 4 bytes/location == 72 bytes -> ceil power of 2 -> 128 bytes
        //       
        //       [1] the ST docs for STM32F7 don't mention that the content of the FIFO RAM can be
        //           accessed for debugging, but the STM32F405 reference manual does, and the same
        //           region offset works with STM32F7.
        //             
        //             - STM32F405 reference manual "USB on-the-go high-speed (OTG_HS)" section
        //               - Subsection "CSR memory map"
        //                 - "Direct access to data FIFO RAM for debugging" at offset "2 0000h"
        //             - Absolute address of FIFO RAM on STM32F7 is USB_OTG_HS+0x20000==0x40060000
        
        constexpr size_t FIFOCapTotal           = 4096;
        constexpr size_t FIFOCapDMARegisters    = (DMAEn ? 128 : 0);
        constexpr size_t FIFOCapUsable          = FIFOCapTotal-FIFOCapDMARegisters;
        constexpr size_t FIFOCapRx              = FIFORxSize();
        constexpr size_t FIFOCapTxCtrl          = USB_MAX_EP0_SIZE;
        // Verify that we haven't already overflowed FIFOCapUsable
        static_assert((FIFOCapRx+FIFOCapTxCtrl) <= FIFOCapUsable);
        constexpr size_t FIFOCapTxBulk          = (FIFOCapUsable-(FIFOCapRx+FIFOCapTxCtrl))/EndpointCountIn();
        // Verify that FIFOCapTxBulk is large enough to hold an IN packet
        static_assert(FIFOCapTxBulk >= MaxPacketSizeIn());
        // Verify that the total memory allocated fits within the FIFO memory.
        static_assert(FIFOCapRx+FIFOCapTxCtrl+(FIFOCapTxBulk*EndpointCountIn()) <= FIFOCapUsable);
        
        // # Set Rx FIFO sizes, shared by all OUT endpoints (GRXFSIZ register):
        //   "The OTG peripheral uses a single receive FIFO that receives
        //   the data directed to all OUT endpoints."
        HAL_PCDEx_SetRxFiFo(&_pcd, FIFOCapRx/sizeof(uint32_t));
        
        // # Set Tx FIFO size for control IN endpoint (DIEPTXF0 register)
        HAL_PCDEx_SetTxFiFo(&_pcd, 0, FIFOCapTxCtrl/sizeof(uint32_t));
        
        // # Set Tx FIFO size for bulk IN endpoints (DIEPTXFx register)
        for (uint8_t ep : {Endpoints...}) {
            if (EndpointIn(ep)) {
                HAL_PCDEx_SetTxFiFo(&_pcd, EndpointIdx(ep), FIFOCapTxBulk/sizeof(uint32_t));
            }
        }
    }
    
    // Accessors
    State state() const {
        return _state;
    }
    
    // Channels
    Channel<Event, 1> eventChannel;
    
//protected:
    void _isr() {
        ISR_HAL_PCD(&_pcd);
    }
    
    USBD_HandleTypeDef _device;
    PCD_HandleTypeDef _pcd;
    State _state = State::Disconnected;
    
    uint8_t _usbd_Init(uint8_t cfgidx) {
        _state = State::Connected;
        eventChannel.writeTry(Event{
            .type = Event::Type::StateChanged,
        });
        
        // Open endpoints
        for (uint8_t ep : {Endpoints...}) {
            if (EndpointOut(ep)) {
                USBD_LL_OpenEP(&_device, ep, USBD_EP_TYPE_BULK, MaxPacketSizeOut());
                _device.ep_out[EndpointIdx(ep)].is_used = 1U;
            
            } else {
                USBD_LL_OpenEP(&_device, ep, USBD_EP_TYPE_BULK, MaxPacketSizeIn());
                _device.ep_in[EndpointIdx(ep)].is_used = 1U;
            }
        }
        
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_DeInit(uint8_t cfgidx) {
        _state = State::Disconnected;
        eventChannel.writeTry(Event{
            .type = Event::Type::StateChanged,
        });
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_Setup(USBD_SetupReqTypedef* req) {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_EP0_TxSent() {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_EP0_RxReady() {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_DataIn(uint8_t epnum) {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_DataOut(uint8_t epnum) {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_SOF() {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_IsoINIncomplete(uint8_t epnum) {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_IsoOUTIncomplete(uint8_t epnum) {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t* _usbd_GetHSConfigDescriptor(uint16_t* len) {
        return nullptr;
    }
    
    uint8_t* _usbd_GetFSConfigDescriptor(uint16_t* len) {
        return nullptr;
    }
    
    uint8_t* _usbd_GetOtherSpeedConfigDescriptor(uint16_t* len) {
        return nullptr;
    }
    
    uint8_t* _usbd_GetDeviceQualifierDescriptor(uint16_t* len) {
        return nullptr;
    }
    
    uint8_t* _usbd_GetUsrStrDescriptor(uint8_t index, uint16_t* len) {
        return nullptr;
    }
    
    friend void ISR_OTG_HS();
};

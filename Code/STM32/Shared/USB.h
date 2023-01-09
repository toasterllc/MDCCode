#pragma once
#include <initializer_list>
#include <optional>
#include "Assert.h"
#include "stm32f7xx.h"
#include "usbd_def.h"
#include "usbd_core.h"
#include "usbd_desc.h"
#include "Toastbox/USB.h"
#include "Toastbox/Scheduler.h"

template <
typename T_Scheduler,   // T_Scheduler: scheduler
bool T_DMAEn,           // T_DMAEn: whether DMA is enabled
typename T_Config       // T_ConfigDesc: contains endpoints and configuration descriptor
>
class USBType {
public:
    struct Cmd {
        const uint8_t* data;
        size_t len;
    };
    
private:
    enum class _EndpointState : uint8_t {
        Ready,
        Busy,
        Done,
        
        Reset,
        ResetZLP1,
        ResetZLP2,
        ResetSentinel,
    };
    
    struct _OutEndpoint {
        _EndpointState state = _EndpointState::Ready;
        size_t len = 0;
        bool needsReset = false;
    };
    
    struct _InEndpoint {
        _EndpointState state = _EndpointState::Ready;
        bool needsReset = false;
    };
    
public:
    static constexpr size_t MaxPacketSizeCtrl = Toastbox::USB::Endpoint::MaxPacketSizeCtrl;
    static constexpr size_t MaxPacketSizeBulk = Toastbox::USB::Endpoint::MaxPacketSizeBulk;
    
    static constexpr auto EndpointIdx = Toastbox::USB::Endpoint::Idx;
    static constexpr auto EndpointOut = Toastbox::USB::Endpoint::Out;
    static constexpr auto EndpointIn = Toastbox::USB::Endpoint::In;
    
    static constexpr size_t EndpointCountOut() {
        return Toastbox::USB::Endpoint::CountOut(T_Config::Endpoints);
    }
    
    static constexpr size_t EndpointCountIn() {
        return Toastbox::USB::Endpoint::CountIn(T_Config::Endpoints);
    }
    
    static constexpr size_t EndpointCount() {
        return std::size(T_Config::Endpoints);
    }
    
    static constexpr size_t MaxPacketSizeIn() {
        return Toastbox::USB::Endpoint::MaxPacketSizeIn(T_Config::Endpoints);
    }
    
    static constexpr size_t MaxPacketSizeOut() {
        return Toastbox::USB::Endpoint::MaxPacketSizeOut(T_Config::Endpoints);
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
    
    static constexpr size_t CeilToMaxPacketSize(size_t maxPacketSize, size_t len) {
        // Round `len` up to the nearest packet size, since the USB hardware limits
        // the data received based on packets instead of bytes
        const size_t rem = len%maxPacketSize;
        len += (rem>0 ? maxPacketSize-rem : 0);
        return len;
    }
    
    // Types
    enum class State : uint8_t {
        Disconnected,
        Connecting,
        Connected,
    };
    
    // Initialization
    static void Init() {
        // Enable GPIO clocks
        __HAL_RCC_GPIOB_CLK_ENABLE();
        
        _PCD.pData = &_Device;
        _PCD.Instance = USB_OTG_HS;
        _PCD.Init.dev_endpoints = 9;
        _PCD.Init.dma_enable = T_DMAEn;
        _PCD.Init.phy_itface = USB_OTG_HS_EMBEDDED_PHY;
        _PCD.Init.sof_enable = false;
        _PCD.Init.low_power_enable = false;
        _PCD.Init.lpm_enable = false;
        _PCD.Init.vbus_sensing_enable = false;
        _PCD.Init.use_dedicated_ep1 = false;
        _PCD.Init.use_external_vbus = false;
        
        _Device.pData = &_PCD;
        
        USBD_StatusTypeDef us = USBD_Init(&_Device, &HS_Desc, DEVICE_HS);
        Assert(us == USBD_OK);
        
        HAL_StatusTypeDef hs = HAL_PCD_Init(&_PCD);
        Assert(hs == HAL_OK);
        
#define Fwd0(name) [](USBD_HandleTypeDef* pdev) { return _USBD_##name(); }
#define Fwd1(name, T0) [](USBD_HandleTypeDef* pdev, T0 t0) { return _USBD_##name(t0); }
#define Fwd2(name, T0, T1) [](USBD_HandleTypeDef* pdev, T0 t0, T1 t1) { return _USBD_##name(t0, t1); }
        
        static const USBD_ClassTypeDef usbClass = {
            .Init                           = Fwd1(Init, uint8_t),
            .DeInit                         = Fwd1(DeInit, uint8_t),
            .Suspend                        = Fwd0(Suspend),
            .Resume                         = Fwd0(Resume),
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
        
        us = USBD_RegisterClass(&_Device, &usbClass);
        Assert(us == USBD_OK);
        
        us = USBD_Start(&_Device);
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
        constexpr size_t FIFOCapDMARegisters    = (T_DMAEn ? 128 : 0);
        constexpr size_t FIFOCapUsable          = FIFOCapTotal-FIFOCapDMARegisters;
        constexpr size_t FIFOCapRx              = FIFORxSize();
        constexpr size_t FIFOCapTxCtrl          = MaxPacketSizeCtrl;
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
        HAL_PCDEx_SetRxFiFo(&_PCD, FIFOCapRx/sizeof(uint32_t));
        
        // # Set Tx FIFO size for control IN endpoint (DIEPTXF0 register)
        HAL_PCDEx_SetTxFiFo(&_PCD, 0, FIFOCapTxCtrl/sizeof(uint32_t));
        
        // # Set Tx FIFO size for bulk IN endpoints (DIEPTXFx register)
        for (uint8_t ep : T_Config::Endpoints) {
            if (EndpointIn(ep)) {
                HAL_PCDEx_SetTxFiFo(&_PCD, EndpointIdx(ep), FIFOCapTxBulk/sizeof(uint32_t));
            }
        }
    }
    
    static void EndpointReset(uint8_t ep) {
        Toastbox::IntState ints(false);
        _EndpointReset(ep);
        T_Scheduler::Wait([=] { return _EndpointReady(ep); });
    }
    
    static void EndpointsReset() {
        Toastbox::IntState ints(false);
        for (uint8_t ep : T_Config::Endpoints) {
            _EndpointReset(ep);
        }
        T_Scheduler::Wait([] { return _EndpointsReady(); });
    }
    
    template <typename T>
    static void CmdRecv(T& cmd) {
        for (;;) {
            // Wait until we're in the Connecting state
            {
                Toastbox::IntState ints(false);
                T_Scheduler::Wait([] { return _State == State::Connecting || _State == State::Connected; });
                if (_State == State::Connecting) {
                    // Update our state
                    _State = State::Connected;
                    _CmdRecvLen = std::nullopt;
                }
            }
            
            // Wait for a command
            for (;;) {
                // Disable interrupts
                Toastbox::IntState ints(false);
                
                // Wait for a new command to arrive, or for our state to change
                T_Scheduler::Wait([] { return _CmdRecvLen || _State!=State::Connected; });
                
                // If we're no longer connected, bail and wait to be connected again
                if (_State != State::Connected) break;
                
                // Consume the command
                const size_t len = *_CmdRecvLen;
                _CmdRecvLen = std::nullopt;
                
                // Reject command if the length isn't valid
                if (len != sizeof(T)) {
                    _CmdAccept(false);
                    continue;
                }
                
                // Return command to caller
                memcpy(&cmd, _CmdRecvBuf, len);
                return;
            }
        }
    }
    
//    static void _WaitForConnect() {
//        T_Scheduler::Wait([] { return _State == State::Connected; });
//    }
    
    static void CmdAccept(bool accept) {
        Toastbox::IntState ints(false);
        // Short-circuit if we're not Connected
        if (_State != State::Connected) return;
        _CmdAccept(accept);
    }
    
    static std::optional<size_t> Recv(uint8_t ep, void* data, size_t len) {
        AssertArg(EndpointOut(ep));
        _OutEndpoint& outep = _OutEndpointGet(ep);
        
        {
            Toastbox::IntState ints(false);
            if (_State != State::Connected) return std::nullopt; // Short-circuit if we're not Connected
            
            Assert(_Ready(outep));
            _AdvanceState(ep, outep);
            
            USBD_StatusTypeDef us = USBD_LL_PrepareReceive(&_Device, ep, (uint8_t*)data, len);
            Assert(us == USBD_OK);
        }
        
        auto waitResult = T_Scheduler::Wait([&] { return _Wait(ep, outep); });
        if (!waitResult.ok) return std::nullopt;
        return waitResult.len;
    }
    
    static bool Send(uint8_t ep, const void* data, size_t len) {
        AssertArg(EndpointIn(ep));
        _InEndpoint& inep = _InEndpointGet(ep);
        
        {
            Toastbox::IntState ints(false);
            if (_State != State::Connected) return false; // Short-circuit if we're not Connected
            
            Assert(_Ready(inep));
            _AdvanceState(ep, inep);
            
            USBD_StatusTypeDef us = USBD_LL_Transmit(&_Device, ep, (uint8_t*)data, len);
            Assert(us == USBD_OK);
        }
        
        auto waitResult = T_Scheduler::Wait([&] { return _Wait(ep, inep); });
        return waitResult.ok;
    }
    
    static void ISR() {
        ISR_HAL_PCD(&_PCD);
    }
    
private:
    static uint8_t _USBD_Init(uint8_t cfgidx) {
        // Open endpoints
        for (uint8_t ep : T_Config::Endpoints) {
            if (EndpointOut(ep)) {
                USBD_LL_OpenEP(&_Device, ep, USBD_EP_TYPE_BULK, MaxPacketSizeOut());
                _Device.ep_out[EndpointIdx(ep)].is_used = 1U;
                // Reset endpoint state
                _OutEndpointGet(ep) = {};
            
            } else {
                USBD_LL_OpenEP(&_Device, ep, USBD_EP_TYPE_BULK, MaxPacketSizeIn());
                _Device.ep_in[EndpointIdx(ep)].is_used = 1U;
                // Reset endpoint state
                _InEndpointGet(ep) = {};
            }
        }
        
        _State = State::Connecting;
        
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_DeInit(uint8_t cfgidx) {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_Suspend() {
        if (_State == State::Disconnected) return USBD_OK; // Short-circuit if we're already Disconnected
        
        Init();
        _State = State::Disconnected;
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_Resume() {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_Setup(USBD_SetupReqTypedef* req) {
        switch (req->bmRequest & USB_REQ_TYPE_MASK) {
        case USB_REQ_TYPE_VENDOR:
            USBD_CtlPrepareRx(&_Device, _CmdRecvBuf, sizeof(_CmdRecvBuf));
            return USBD_OK;
        
        default:
            USBD_CtlError(&_Device, req);
            return USBD_FAIL;
        }
    }
    
    static uint8_t _USBD_EP0_TxSent() {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_EP0_RxReady() {
        const size_t recvLen = USBD_LL_GetRxDataSize(&_Device, 0);
        if (!_CmdRecvLen) {
            _CmdRecvLen = recvLen;
        } else {
            // If a command is already underway, respond to the request with an error
            USBD_CtlError(&_Device, nullptr);
        }
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_DataIn(uint8_t ep) {
        // Sanity-check the endpoint state
        _InEndpoint& inep = _InEndpointGet(ep);
        Assert(
            inep.state == _EndpointState::ResetZLP1     ||
            inep.state == _EndpointState::ResetZLP2     ||
            inep.state == _EndpointState::ResetSentinel ||
            inep.state == _EndpointState::Busy
        );
        
        _AdvanceState(ep, inep);
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_DataOut(uint8_t ep) {
        // Sanity-check the endpoint state
        _OutEndpoint& outep = _OutEndpointGet(ep);
        Assert(
            outep.state == _EndpointState::ResetZLP1     ||
            outep.state == _EndpointState::ResetZLP2     ||
            outep.state == _EndpointState::ResetSentinel ||
            outep.state == _EndpointState::Busy
        );
        
        _AdvanceState(ep, outep);
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_SOF() {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_IsoINIncomplete(uint8_t ep) {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_IsoOUTIncomplete(uint8_t ep) {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t* _USBD_GetHSConfigDescriptor(uint16_t* len) {
        *len = sizeof(T_Config::Descriptor);
        return (uint8_t*)&T_Config::Descriptor;
    }
    
    static uint8_t* _USBD_GetFSConfigDescriptor(uint16_t* len) {
        return nullptr;
    }
    
    static uint8_t* _USBD_GetOtherSpeedConfigDescriptor(uint16_t* len) {
        return nullptr;
    }
    
    static uint8_t* _USBD_GetDeviceQualifierDescriptor(uint16_t* len) {
        return nullptr;
    }
    
    static uint8_t* _USBD_GetUsrStrDescriptor(uint8_t index, uint16_t* len) {
        return nullptr;
    }
    
    // Interrupts must be disabled
    static void _CmdAccept(bool accept) {
        if (accept) USBD_CtlSendStatus(&_Device);
        else        USBD_CtlError(&_Device, nullptr);
    }
    
    static _OutEndpoint& _OutEndpointGet(uint8_t ep) {
        if constexpr (EndpointCountOut()) {
            return _OutEndpoints[EndpointIdx(ep)-1];
        }
        abort();
    }
    
//    static const _OutEndpoint& _OutEndpointGet(uint8_t ep) {
//        if constexpr (EndpointCountOut()) {
//            return _OutEndpoints[EndpointIdx(ep)-1];
//        }
//        abort();
////        return const_cast<const _OutEndpoint&>(std::as_const(*this)._OutEndpointGet(ep));
//    }
    
    static _InEndpoint& _InEndpointGet(uint8_t ep) {
        if constexpr (EndpointCountIn()) {
            return _InEndpoints[EndpointIdx(ep)-1];
        }
        abort();
    }
    
    struct _WaitResultOut {
        bool done = false;
        bool ok = false;
        size_t len = 0;
        operator bool() const { return done; }
    };
    
    static _WaitResultOut _Wait(uint8_t ep, _OutEndpoint& outep) {
        Toastbox::IntState ints(false);
        
        // Short-circuit if we're not Connected
        if (_State != State::Connected) return { true, false }; // Done, failed
        
        switch (outep.state) {
        case _EndpointState::Busy:
            // Still waiting for completion
            return { false };
        case _EndpointState::Done:
            // Done, success
            _AdvanceState(ep, outep);
            return { true, true, _RecvLen(outep) };
        default:
            // Done, failed
            return { true, false };
        }
    }
    
    struct _WaitResultIn {
        bool done = false;
        bool ok = false;
        operator bool() const { return done; }
    };
    
    static _WaitResultIn _Wait(uint8_t ep, _InEndpoint& inep) {
        Toastbox::IntState ints(false);
        
        // Short-circuit if we're not Connected
        if (_State != State::Connected) return { true, false }; // Done, failed
        
        switch (inep.state) {
        case _EndpointState::Busy:
            // Still waiting for completion
            return { false };
        case _EndpointState::Done:
            // Done, success
            _AdvanceState(ep, inep);
            return { true, true };
        default:
            // Done, failed
            return { true, false };
        }
    }
    
//    static const _InEndpoint& _InEndpointGet(uint8_t ep) {
//        if constexpr (EndpointCountIn()) {
//            return _InEndpoints[EndpointIdx(ep)-1];
//        }
//        abort();
////        return const_cast<const _InEndpoint&>(std::as_const(*this)._InEndpointGet(ep));
//    }
    
    // Interrupts must be disabled
    static void _EndpointReset(uint8_t ep) {
        if (_State != State::Connected) return; // Short-circuit if we're not Connected
        
        if (EndpointOut(ep)) {
            _OutEndpoint& outep = _OutEndpointGet(ep);
            if (_Ready(outep))  _EndpointReset(ep, outep);
            else                outep.needsReset = true;
        
        } else {
            _InEndpoint& inep = _InEndpointGet(ep);
            if (_Ready(inep))   _EndpointReset(ep, inep);
            else                inep.needsReset = true;
        }
    }
    
    // Interrupts must be disabled
    static bool _EndpointReady(uint8_t ep) {
        if (EndpointOut(ep))    return _Ready(_OutEndpointGet(ep));
        else                    return _Ready(_InEndpointGet(ep));
    }
    
    // Interrupts must be disabled
    static bool _EndpointsReady() {
        for (uint8_t ep : T_Config::Endpoints) {
            if (!_EndpointReady(ep)) return false;
        }
        return true;
    }
    
    // Interrupts must be disabled
    static bool _Ready(const _OutEndpoint& outep)       { return outep.state==_EndpointState::Ready;  }
    static bool _Ready(const _InEndpoint& inep)         { return inep.state==_EndpointState::Ready;   }
    static bool _Busy(const _OutEndpoint& outep)        { return outep.state==_EndpointState::Busy;   }
    static bool _Busy(const _InEndpoint& inep)          { return inep.state==_EndpointState::Busy;    }
    static bool _Done(const _OutEndpoint& outep)        { return outep.state==_EndpointState::Done;   }
    static bool _Done(const _InEndpoint& inep)          { return inep.state==_EndpointState::Done;    }
    
    static size_t _RecvLen(const _OutEndpoint& outep)   { return outep.len;                           }
    
    // Interrupts must be disabled
    template <typename OutInEndpoint>
    static void _EndpointReset(uint8_t ep, OutInEndpoint& outinep) {
        outinep.state = _EndpointState::Reset;
        outinep.needsReset = false;
        _AdvanceState(ep, outinep);
    }
    
    // Interrupts must be disabled
    static void _AdvanceState(uint8_t ep, _OutEndpoint& outep) {
        if (outep.needsReset) {
            _EndpointReset(ep, outep);
            return;
        }
        
        outep.len = USBD_LL_GetRxDataSize(&_Device, ep);
        
        // State transitions
        switch (outep.state) {
        case _EndpointState::Ready:     outep.state = _EndpointState::Busy; break;
        case _EndpointState::Busy:      outep.state = _EndpointState::Done; break;
        case _EndpointState::Done:      outep.state = _EndpointState::Ready; break;
        case _EndpointState::Reset:     outep.state = _EndpointState::ResetZLP1; break;
        case _EndpointState::ResetZLP1:
            // Only advance if we received a ZLP
            if (outep.len == 0) outep.state = _EndpointState::ResetSentinel;
            break;
        case _EndpointState::ResetSentinel:
            // Only advance if we received the sentinel
            if (outep.len == sizeof(_ResetSentinel)) outep.state = _EndpointState::Ready;
            break;
        default:
            abort();
        }
        
        // State actions
        switch (outep.state) {
        case _EndpointState::ResetZLP1:
        case _EndpointState::ResetSentinel:
            USBD_LL_PrepareReceive(&_Device, ep, (uint8_t*)_DevNullAddr, MaxPacketSizeBulk);
            break;
        default:
            break;
        }
    }
    
    // Interrupts must be disabled
    static void _AdvanceState(uint8_t ep, _InEndpoint& inep) {
        if (inep.needsReset) {
            _EndpointReset(ep, inep);
            return;
        }
        
        // We send two ZLPs (instead of just one) because if a transfer is in progress, the first ZLP will
        // get 'eaten' as a ZLP that terminates the existing transfer. So to guarantee that the reader
        // actually gets a ZLP, we have to send two.
        // After sending the two ZLPs, we also send a sentinel to account for the fact that we don't know
        // how many ZLPs that the reader will receive, because we don't know if the first ZLP will
        // necessarily terminate a transfer (because a transfer may not have been in progress, or if a
        // transfer was in progress, it may have sent exactly the number of bytes that the reader
        // requested, in which case no ZLP is needed to end the transfer). By using a sentinel, the
        // reader knows that no further ZLPs will be received after the sentinel has been received, and
        // therefore the endpoint is finished being reset.
        
        // State transitions
        switch (inep.state) {
        case _EndpointState::Ready:         inep.state = _EndpointState::Busy;          break;
        case _EndpointState::Busy:          inep.state = _EndpointState::Done;          break;
        case _EndpointState::Done:          inep.state = _EndpointState::Ready;         break;
        case _EndpointState::Reset:         inep.state = _EndpointState::ResetZLP1;     break;
        case _EndpointState::ResetZLP1:     inep.state = _EndpointState::ResetZLP2;     break;
        case _EndpointState::ResetZLP2:     inep.state = _EndpointState::ResetSentinel; break;
        case _EndpointState::ResetSentinel: inep.state = _EndpointState::Ready;         break;
        default:                            abort();
        }
        
        // State actions
        switch (inep.state) {
        case _EndpointState::ResetZLP1:
        case _EndpointState::ResetZLP2:
            USBD_LL_TransmitZeroLen(&_Device, ep);
            break;
        case _EndpointState::ResetSentinel:
            USBD_LL_Transmit(&_Device, ep, (uint8_t*)&_ResetSentinel, sizeof(_ResetSentinel));
            break;
        default:
            break;
        }
    }
    
private:
    alignas(4) static const inline uint8_t _ResetSentinel = 0; // Aligned to send via USB
    
    // _DevNullAddr: address that throw-away data can be written to.
    // This must be a region that a packet can be written to without causing
    // side-effects. We don't want to reserve actual RAM for this because it'd
    // just be wasted.
    // We're currently using the flash base address, so that the writes will be
    // ignored as long as the flash isn't unlocked.
    static constexpr uint32_t _DevNullAddr = 0x08000000;
    
    alignas(4) static inline uint8_t _CmdRecvBuf[MaxPacketSizeCtrl]; // Aligned to receive via USB
    static inline std::optional<size_t> _CmdRecvLen;
    static inline _OutEndpoint _OutEndpoints[EndpointCountOut()] = {};
    static inline _InEndpoint _InEndpoints[EndpointCountIn()] = {};
    static inline USBD_HandleTypeDef _Device;
    static inline PCD_HandleTypeDef _PCD;
    static inline State _State = State::Disconnected;
};

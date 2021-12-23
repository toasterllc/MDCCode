#pragma once
#include <initializer_list>
#include <optional>
#include "Assert.h"
#include "stm32f7xx.h"
#include "usbd_def.h"
#include "usbd_core.h"
#include "usbd_desc.h"
#include "Toastbox/USB.h"
#include "Toastbox/IntState.h"

template <
bool T_DMAEn,                       // T_DMAEn: whether DMA is enabled
const void* T_ConfigDesc(size_t&),  // T_ConfigDesc: returns USB configuration descriptor
uint8_t... T_Endpoints              // T_Endpoints: list of endpoints
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
    
    static constexpr uint8_t EndpointIdx(uint8_t ep)    { return ep&0xF;        }
    static constexpr bool EndpointOut(uint8_t ep)       { return !(ep&0x80);    }
    static constexpr bool EndpointIn(uint8_t ep)        { return  (ep&0x80);    }
    
    static constexpr size_t EndpointCountOut() {
        size_t count = 0;
        for (uint8_t ep : {T_Endpoints...}) count += EndpointOut(ep);
        return count;
    }
    
    static constexpr size_t EndpointCountIn() {
        size_t count = 0;
        for (uint8_t ep : {T_Endpoints...}) count += EndpointIn(ep);
        return count;
    }
    
    static constexpr size_t EndpointCount() {
        return sizeof...(T_Endpoints);
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
    enum class State : uint8_t {
        Disconnected,
        Connecting,
        Connected,
    };
    
    // Initialization
    void init() {
        _pcd.pData = &_device;
        _pcd.Instance = USB_OTG_HS;
        _pcd.Init.dev_endpoints = 9;
        _pcd.Init.dma_enable = T_DMAEn;
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
        
#define Fwd0(name) [](USBD_HandleTypeDef* pdev) { return ((USBType*)pdev->pCtx)->_usbd_##name(); }
#define Fwd1(name, T0) [](USBD_HandleTypeDef* pdev, T0 t0) { return ((USBType*)pdev->pCtx)->_usbd_##name(t0); }
#define Fwd2(name, T0, T1) [](USBD_HandleTypeDef* pdev, T0 t0, T1 t1) { return ((USBType*)pdev->pCtx)->_usbd_##name(t0, t1); }
        
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
        HAL_PCDEx_SetRxFiFo(&_pcd, FIFOCapRx/sizeof(uint32_t));
        
        // # Set Tx FIFO size for control IN endpoint (DIEPTXF0 register)
        HAL_PCDEx_SetTxFiFo(&_pcd, 0, FIFOCapTxCtrl/sizeof(uint32_t));
        
        // # Set Tx FIFO size for bulk IN endpoints (DIEPTXFx register)
        for (uint8_t ep : {T_Endpoints...}) {
            if (EndpointIn(ep)) {
                HAL_PCDEx_SetTxFiFo(&_pcd, EndpointIdx(ep), FIFOCapTxBulk/sizeof(uint32_t));
            }
        }
    }
    
    // Accessors
    State state() const {
        Toastbox::IntState ints(false);
        return _state;
    }
    
    // Methods
    void connect() {
        Toastbox::IntState ints(false);
        if (_state != State::Connecting) return; // Short-circuit if we're not Connecting
        _state = State::Connected;
    }
    
    void endpointReset(uint8_t ep) {
        Toastbox::IntState ints(false);
        _endpointReset(ep);
    }
    
    void endpointsReset() {
        Toastbox::IntState ints(false);
        for (uint8_t ep : {T_Endpoints...}) {
            _endpointReset(ep);
        }
    }
    
    bool endpointReady(uint8_t ep) {
        Toastbox::IntState ints(false);
        return _endpointReady(ep);
    }
    
    bool endpointsReady() {
        Toastbox::IntState ints(false);
        for (uint8_t ep : {T_Endpoints...}) {
            if (!_endpointReady(ep)) return false;
        }
        return true;
    }
    
    std::optional<Cmd> cmdRecv() {
        Toastbox::IntState ints(false);
        if (_state != State::Connected) return std::nullopt; // Short-circuit if we're not Connected
        return _cmd;
    }
    
    void cmdAccept(bool accept) {
        Toastbox::IntState ints(false);
        if (_state != State::Connected) return; // Short-circuit if we're not Connected
        
        if (accept) USBD_CtlSendStatus(&_device);
        else        USBD_CtlError(&_device, nullptr);
        
        _cmd = std::nullopt;
    }
    
    void recv(uint8_t ep, void* data, size_t len) {
        AssertArg(EndpointOut(ep));
        
        Toastbox::IntState ints(false);
        if (_state != State::Connected) return; // Short-circuit if we're not Connected
        
        _OutEndpoint& outep = _outEndpoint(ep);
        Assert(_ready(outep));
        _advanceState(ep, outep);
        
        USBD_StatusTypeDef us = USBD_LL_PrepareReceive(&_device, ep, (uint8_t*)data, len);
        Assert(us == USBD_OK);
    }
    
    size_t recvLen(uint8_t ep) const {
        AssertArg(EndpointOut(ep));
        
        Toastbox::IntState ints(false);
        if (_state != State::Connected) return 0; // Short-circuit if we're not Connected
        return _recvLen(_outEndpoint(ep));
    }
    
    void send(uint8_t ep, const void* data, size_t len) {
        AssertArg(EndpointIn(ep));
        
        Toastbox::IntState ints(false);
        if (_state != State::Connected) return; // Short-circuit if we're not Connected
        
        _InEndpoint& inep = _inEndpoint(ep);
        Assert(_ready(inep));
        _advanceState(ep, inep);
        
        USBD_StatusTypeDef us = USBD_LL_Transmit(&_device, ep, (uint8_t*)data, len);
        Assert(us == USBD_OK);
    }
    
    void isr() {
        ISR_HAL_PCD(&_pcd);
    }
    
protected:
    uint8_t _usbd_Init(uint8_t cfgidx) {
        // Open endpoints
        for (uint8_t ep : {T_Endpoints...}) {
            if (EndpointOut(ep)) {
                USBD_LL_OpenEP(&_device, ep, USBD_EP_TYPE_BULK, MaxPacketSizeOut());
                _device.ep_out[EndpointIdx(ep)].is_used = 1U;
                // Reset endpoint state
                _outEndpoint(ep) = {};
            
            } else {
                USBD_LL_OpenEP(&_device, ep, USBD_EP_TYPE_BULK, MaxPacketSizeIn());
                _device.ep_in[EndpointIdx(ep)].is_used = 1U;
                // Reset endpoint state
                _inEndpoint(ep) = {};
            }
        }
        
        _cmd = std::nullopt;
        _state = State::Connecting;
        
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_DeInit(uint8_t cfgidx) {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_Suspend() {
        if (_state == State::Disconnected) return USBD_OK; // Short-circuit if we're already Disconnected
        
        init();
        _state = State::Disconnected;
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_Resume() {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_Setup(USBD_SetupReqTypedef* req) {
        switch (req->bmRequest & USB_REQ_TYPE_MASK) {
        case USB_REQ_TYPE_VENDOR:
            USBD_CtlPrepareRx(&_device, _cmdRecvBuf, sizeof(_cmdRecvBuf));
            return USBD_OK;
        
        default:
            USBD_CtlError(&_device, req);
            return USBD_FAIL;
        }
    }
    
    uint8_t _usbd_EP0_TxSent() {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_EP0_RxReady() {
        const size_t dataLen = USBD_LL_GetRxDataSize(&_device, 0);
        if (!_cmd) {
            _cmd = Cmd{
                .data = _cmdRecvBuf,
                .len = dataLen,
            };
        } else {
            // If a command is already underway, respond to the request with an error
            USBD_CtlError(&_device, nullptr);
        }
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_DataIn(uint8_t ep) {
        // Sanity-check the endpoint state
        _InEndpoint& inep = _inEndpoint(ep);
        Assert(
            inep.state == _EndpointState::ResetZLP1     ||
            inep.state == _EndpointState::ResetZLP2     ||
            inep.state == _EndpointState::ResetSentinel ||
            inep.state == _EndpointState::Busy
        );
        
        _advanceState(ep, inep);
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_DataOut(uint8_t ep) {
        // Sanity-check the endpoint state
        _OutEndpoint& outep = _outEndpoint(ep);
        Assert(
            outep.state == _EndpointState::ResetZLP1     ||
            outep.state == _EndpointState::ResetZLP2     ||
            outep.state == _EndpointState::ResetSentinel ||
            outep.state == _EndpointState::Busy
        );
        
        _advanceState(ep, outep);
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_SOF() {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_IsoINIncomplete(uint8_t ep) {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t _usbd_IsoOUTIncomplete(uint8_t ep) {
        return (uint8_t)USBD_OK;
    }
    
    uint8_t* _usbd_GetHSConfigDescriptor(uint16_t* len) {
        size_t descLen = 0;
        const void*const desc = T_ConfigDesc(descLen);
        *len = descLen;
        return (uint8_t*)desc;
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

private:
    _OutEndpoint& _outEndpoint(uint8_t ep) {
        if constexpr (EndpointCountOut()) {
            return _outEndpoints[EndpointIdx(ep)-1];
        }
        abort();
    }
    
    const _OutEndpoint& _outEndpoint(uint8_t ep) const {
        if constexpr (EndpointCountOut()) {
            return _outEndpoints[EndpointIdx(ep)-1];
        }
        abort();
//        return const_cast<const _OutEndpoint&>(std::as_const(*this)._outEndpoint(ep));
    }
    
    _InEndpoint& _inEndpoint(uint8_t ep) {
        if constexpr (EndpointCountIn()) {
            return _inEndpoints[EndpointIdx(ep)-1];
        }
        abort();
    }
    
    const _InEndpoint& _inEndpoint(uint8_t ep) const {
        if constexpr (EndpointCountIn()) {
            return _inEndpoints[EndpointIdx(ep)-1];
        }
        abort();
//        return const_cast<const _InEndpoint&>(std::as_const(*this)._inEndpoint(ep));
    }
    
    // Interrupts must be disabled
    void _endpointReset(uint8_t ep) {
        if (_state != State::Connected) return; // Short-circuit if we're not Connected
        
        if (EndpointOut(ep)) {
            _OutEndpoint& outep = _outEndpoint(ep);
            if (_ready(outep))  _endpointReset(ep, outep);
            else                outep.needsReset = true;
        
        } else {
            _InEndpoint& inep = _inEndpoint(ep);
            if (_ready(inep))   _endpointReset(ep, inep);
            else                inep.needsReset = true;
        }
    }
    
    // Interrupts must be disabled
    bool _endpointReady(uint8_t ep) {
        if (_state != State::Connected) return false; // Short-circuit if we're not Connected
        if (EndpointOut(ep))    return _ready(_outEndpoint(ep));
        else                    return _ready(_inEndpoint(ep));
    }
    
    // Interrupts must be disabled
    bool _ready(const _OutEndpoint& outep)      const { return outep.state==_EndpointState::Ready;  }
    // Interrupts must be disabled
    bool _ready(const _InEndpoint& inep)        const { return inep.state==_EndpointState::Ready;   }
    
    size_t _recvLen(const _OutEndpoint& outep)  const { return outep.len;                           }
    
    // Interrupts must be disabled
    template <typename OutInEndpoint>
    void _endpointReset(uint8_t ep, OutInEndpoint& outinep) {
        outinep.state = _EndpointState::Reset;
        outinep.needsReset = false;
        _advanceState(ep, outinep);
    }
    
    // Interrupts must be disabled
    void _advanceState(uint8_t ep, _OutEndpoint& outep) {
        if (outep.needsReset) {
            _endpointReset(ep, outep);
            return;
        }
        
        outep.len = USBD_LL_GetRxDataSize(&_device, ep);
        
        // State transitions
        switch (outep.state) {
        case _EndpointState::Ready:
            outep.state = _EndpointState::Busy;
            break;
        case _EndpointState::Busy:
            outep.state = _EndpointState::Ready;
            break;
        case _EndpointState::Reset:
            outep.state = _EndpointState::ResetZLP1;
            break;
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
            USBD_LL_PrepareReceive(&_device, ep, (uint8_t*)_DevNullAddr, MaxPacketSizeBulk);
            break;
        default:
            break;
        }
    }
    
    // Interrupts must be disabled
    void _advanceState(uint8_t ep, _InEndpoint& inep) {
        if (inep.needsReset) {
            _endpointReset(ep, inep);
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
        case _EndpointState::Busy:          inep.state = _EndpointState::Ready;         break;
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
            USBD_LL_TransmitZeroLen(&_device, ep);
            break;
        case _EndpointState::ResetSentinel:
            USBD_LL_Transmit(&_device, ep, (uint8_t*)&_ResetSentinel, sizeof(_ResetSentinel));
            break;
        default:
            break;
        }
    }
    
protected:
    USBD_HandleTypeDef _device;
    
private:
    alignas(4) static const inline uint8_t _ResetSentinel = 0; // Aligned to send via USB
    
    // _DevNullAddr: address that throw-away data can be written to.
    // This must be a region that a packet can be written to without causing
    // side-effects. We don't want to reserve actual RAM for this because it'd
    // just be wasted.
    // We're currently using the flash base address, so that the writes will be
    // ignored as long as the flash isn't unlocked.
    static constexpr uint32_t _DevNullAddr = 0x08000000;
    
    std::optional<Cmd> _cmd;
    alignas(4) uint8_t _cmdRecvBuf[MaxPacketSizeCtrl]; // Aligned to send via USB
    _OutEndpoint _outEndpoints[EndpointCountOut()] = {};
    _InEndpoint _inEndpoints[EndpointCountIn()] = {};
    PCD_HandleTypeDef _pcd;
    State _state = State::Disconnected;
};

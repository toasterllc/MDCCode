#pragma once
#include "Assert.h"
#include "Channel.h"
#include "stm32f7xx.h"
#include "usbd_def.h"
#include "usbd_core.h"
//#include "usbd_ctlreq.h"
#include "usbd_desc.h"
//#include "usbd_ioreq.h"

extern "C" void ISR_OTG_HS();

template <typename T>
class USBBase {
public:
    static constexpr uint8_t EndpointNum(uint8_t epaddr) {
        return epaddr&0xF;
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
    void init(bool dmaEnable) {
        USBD_StatusTypeDef us = USBD_Init(&_device, &HS_Desc, DEVICE_HS, this);
        Assert(us == USBD_OK);
        
        _pcd.pData = &_device;
        _device.pData = &_pcd;
        
        _pcd.Instance = USB_OTG_HS;
        _pcd.Init.dev_endpoints = 9;
        _pcd.Init.dma_enable = dmaEnable;
        _pcd.Init.phy_itface = USB_OTG_HS_EMBEDDED_PHY;
        _pcd.Init.sof_enable = false;
        _pcd.Init.low_power_enable = false;
        _pcd.Init.lpm_enable = false;
        _pcd.Init.vbus_sensing_enable = false;
        _pcd.Init.use_dedicated_ep1 = false;
        _pcd.Init.use_external_vbus = false;
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
    }
    
    // Accessors
    State state() const {
        return _state;
    }
    
    // Channels
    Channel<Event, 1> eventChannel;
    
protected:
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

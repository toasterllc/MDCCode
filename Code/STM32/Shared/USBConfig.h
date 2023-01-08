#pragma once
#include "Toastbox/USB.h"
#include "Toastbox/Endian.h"
#include "STM.h"

struct USBConfig {
private:
    static constexpr auto _LFH_U8 = Toastbox::Endian::LFH_U8;
    static constexpr auto _LFH_U16 = Toastbox::Endian::LFH_U16;
    
    struct [[gnu::packed]] _Data {
        Toastbox::USB::ConfigurationDescriptor configDesc;
        Toastbox::USB::InterfaceDescriptor iface0Desc;
            Toastbox::USB::EndpointDescriptor epOut1Desc;
            Toastbox::USB::EndpointDescriptor epIn1Desc;
    };
    
public:
    static constexpr inline uint8_t Endpoints[] = {
        (uint8_t)STM::Endpoint::DataOut,
        (uint8_t)STM::Endpoint::DataIn,
    };
    
    alignas(4)
    static constexpr inline _Data Descriptor = {
        .configDesc = {
            .bLength                        = _LFH_U8(sizeof(Toastbox::USB::ConfigurationDescriptor)),   // bLength: configuration descriptor length
            .bDescriptorType                = _LFH_U8(Toastbox::USB::DescriptorType::Configuration),     // bDescriptorType: configuration descriptor
            .wTotalLength                   = _LFH_U16(sizeof(_Data)),                                   // wTotalLength: total descriptor length
            .bNumInterfaces                 = _LFH_U8(0x01),                                             // bNumInterfaces: 1 interface
            .bConfigurationValue            = _LFH_U8(0x01),                                             // bConfigurationValue: config 1
            .iConfiguration                 = _LFH_U8(0x00),                                             // iConfiguration: string descriptor index
            .bmAttributes                   = _LFH_U8(0x80),                                             // bmAttributes: bus powered
            .bMaxPower                      = _LFH_U8(0xFA),                                             // bMaxPower: 500 mA (2 mA units)
        },
        
            .iface0Desc = {
                .bLength                    = _LFH_U8(sizeof(Toastbox::USB::InterfaceDescriptor)),       // bLength: interface descriptor length
                .bDescriptorType            = _LFH_U8(Toastbox::USB::DescriptorType::Interface),         // bDescriptorType: interface descriptor
                .bInterfaceNumber           = _LFH_U8(0x00),                                             // bInterfaceNumber: interface index
                .bAlternateSetting          = _LFH_U8(0x00),                                             // bAlternateSetting: alternate setting
                .bNumEndpoints              = _LFH_U8(std::size(Endpoints)),                             // bNumEndpoints
                .bInterfaceClass            = _LFH_U8(0xFF),                                             // bInterfaceClass: vendor specific
                .bInterfaceSubClass         = _LFH_U8(0x00),                                             // bInterfaceSubClass
                .bInterfaceProtocol         = _LFH_U8(0x00),                                             // nInterfaceProtocol
                .iInterface                 = _LFH_U8(0x00),                                             // iInterface: string descriptor index
            },
            
                .epOut1Desc = {
                    .bLength                = _LFH_U8(sizeof(Toastbox::USB::EndpointDescriptor)),               // bLength: Endpoint Descriptor size
                    .bDescriptorType        = _LFH_U8(Toastbox::USB::DescriptorType::Endpoint),                 // bDescriptorType: Endpoint
                    .bEndpointAddress       = _LFH_U8(STM::Endpoint::DataOut),                                 // bEndpointAddress
                    .bmAttributes           = _LFH_U8(Toastbox::USB::EndpointAttributes::TransferBulk),         // bmAttributes: Bulk
                    .wMaxPacketSize         = _LFH_U16(Toastbox::USB::Endpoint::MaxPacketSizeOut(Endpoints)),   // wMaxPacketSize
                    .bInterval              = _LFH_U8(0x00),                                                    // bInterval: ignore for Bulk transfer
                },
                
                .epIn1Desc = {
                    .bLength                = _LFH_U8(sizeof(Toastbox::USB::EndpointDescriptor)),               // bLength: Endpoint Descriptor size
                    .bDescriptorType        = _LFH_U8(Toastbox::USB::DescriptorType::Endpoint),                 // bDescriptorType: Endpoint
                    .bEndpointAddress       = _LFH_U8(STM::Endpoint::DataIn),                                  // bEndpointAddress
                    .bmAttributes           = _LFH_U8(Toastbox::USB::EndpointAttributes::TransferBulk),         // bmAttributes: Bulk
                    .wMaxPacketSize         = _LFH_U16(Toastbox::USB::Endpoint::MaxPacketSizeIn(Endpoints)),    // wMaxPacketSize
                    .bInterval              = _LFH_U8(0x00),                                                    // bInterval: ignore for Bulk transfer
                },
    };
};

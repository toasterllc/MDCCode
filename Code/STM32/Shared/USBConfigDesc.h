#pragma once
#include "Toastbox/USB.h"
#include "Toastbox/Endian.h"

template <typename T_USB>
struct USBConfigDesc {
    static constexpr auto LFH_U8 = Toastbox::Endian::LFH_U8;
    static constexpr auto LFH_U16 = Toastbox::Endian::LFH_U16;
    
    struct [[gnu::packed]] DataType {
        Toastbox::USB::ConfigurationDescriptor configDesc;
        Toastbox::USB::InterfaceDescriptor iface0Desc;
            Toastbox::USB::EndpointDescriptor epOut1Desc;
            Toastbox::USB::EndpointDescriptor epIn1Desc;
    };
    
    alignas(4)
    static const inline DataType Data = {
        .configDesc = {
            .bLength                        = LFH_U8(sizeof(Toastbox::USB::ConfigurationDescriptor)),   // bLength: configuration descriptor length
            .bDescriptorType                = LFH_U8(Toastbox::USB::DescriptorType::Configuration),     // bDescriptorType: configuration descriptor
            .wTotalLength                   = LFH_U16(sizeof(USBConfigDesc)),                           // wTotalLength: total descriptor length
            .bNumInterfaces                 = LFH_U8(0x01),                                             // bNumInterfaces: 1 interface
            .bConfigurationValue            = LFH_U8(0x01),                                             // bConfigurationValue: config 1
            .iConfiguration                 = LFH_U8(0x00),                                             // iConfiguration: string descriptor index
            .bmAttributes                   = LFH_U8(0x80),                                             // bmAttributes: bus powered
            .bMaxPower                      = LFH_U8(0xFA),                                             // bMaxPower: 500 mA (2 mA units)
        },
        
            .iface0Desc = {
                .bLength                    = LFH_U8(sizeof(Toastbox::USB::InterfaceDescriptor)),       // bLength: interface descriptor length
                .bDescriptorType            = LFH_U8(Toastbox::USB::DescriptorType::Interface),         // bDescriptorType: interface descriptor
                .bInterfaceNumber           = LFH_U8(0x00),                                             // bInterfaceNumber: interface index
                .bAlternateSetting          = LFH_U8(0x00),                                             // bAlternateSetting: alternate setting
                .bNumEndpoints              = LFH_U8(T_USB::EndpointCount()),                           // bNumEndpoints
                .bInterfaceClass            = LFH_U8(0xFF),                                             // bInterfaceClass: vendor specific
                .bInterfaceSubClass         = LFH_U8(0x00),                                             // bInterfaceSubClass
                .bInterfaceProtocol         = LFH_U8(0x00),                                             // nInterfaceProtocol
                .iInterface                 = LFH_U8(0x00),                                             // iInterface: string descriptor index
            },
            
                .epOut1Desc = {
                    .bLength                = LFH_U8(sizeof(Toastbox::USB::EndpointDescriptor)),        // bLength: Endpoint Descriptor size
                    .bDescriptorType        = LFH_U8(Toastbox::USB::DescriptorType::Endpoint),          // bDescriptorType: Endpoint
                    .bEndpointAddress       = LFH_U8(STM::Endpoints::DataOut),                          // bEndpointAddress
                    .bmAttributes           = LFH_U8(Toastbox::USB::EndpointAttributes::TransferBulk),  // bmAttributes: Bulk
                    .wMaxPacketSize         = LFH_U16(T_USB::MaxPacketSizeOut()),                       // wMaxPacketSize
                    .bInterval              = LFH_U8(0x00),                                             // bInterval: ignore for Bulk transfer
                },
                
                .epIn1Desc = {
                    .bLength                = LFH_U8(sizeof(Toastbox::USB::EndpointDescriptor)),        // bLength: Endpoint Descriptor size
                    .bDescriptorType        = LFH_U8(Toastbox::USB::DescriptorType::Endpoint),          // bDescriptorType: Endpoint
                    .bEndpointAddress       = LFH_U8(STM::Endpoints::DataIn),                           // bEndpointAddress
                    .bmAttributes           = LFH_U8(Toastbox::USB::EndpointAttributes::TransferBulk),  // bmAttributes: Bulk
                    .wMaxPacketSize         = LFH_U16(T_USB::MaxPacketSizeIn()),                        // wMaxPacketSize
                    .bInterval              = LFH_U8(0x00),                                             // bInterval: ignore for Bulk transfer
                },
    };
};

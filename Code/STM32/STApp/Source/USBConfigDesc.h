#pragma once
#include "Toastbox/USB.h"
#include "Toastbox/Endian.h"

template <typename T_USB>
static const void* USBConfigDesc(size_t& len) {
    using namespace Toastbox;
    using namespace Toastbox::Endian;
    
    struct USBConfigDescType {
        USB::ConfigurationDescriptor configDesc;
        USB::InterfaceDescriptor iface0Desc;
            USB::EndpointDescriptor epOut1Desc;
            USB::EndpointDescriptor epIn1Desc;
    } __attribute__((packed));
    
    alignas(4) static const USBConfigDescType USBConfigDesc = {
        .configDesc = {
            .bLength                        = LFH_U8(sizeof(USB::ConfigurationDescriptor)),     // bLength: configuration descriptor length
            .bDescriptorType                = LFH_U8(USB::DescriptorType::Configuration),       // bDescriptorType: configuration descriptor
            .wTotalLength                   = LFH_U16(sizeof(USBConfigDesc)),                   // wTotalLength: total descriptor length
            .bNumInterfaces                 = LFH_U8(0x01),                                     // bNumInterfaces: 1 interface
            .bConfigurationValue            = LFH_U8(0x01),                                     // bConfigurationValue: config 1
            .iConfiguration                 = LFH_U8(0x00),                                     // iConfiguration: string descriptor index
            .bmAttributes                   = LFH_U8(0x80),                                     // bmAttributes: bus powered
            .bMaxPower                      = LFH_U8(0xFA),                                     // bMaxPower: 500 mA (2 mA units)
        },
        
            .iface0Desc = {
                .bLength                    = LFH_U8(sizeof(USB::InterfaceDescriptor)),         // bLength: interface descriptor length
                .bDescriptorType            = LFH_U8(USB::DescriptorType::Interface),           // bDescriptorType: interface descriptor
                .bInterfaceNumber           = LFH_U8(0x00),                                     // bInterfaceNumber: interface index
                .bAlternateSetting          = LFH_U8(0x00),                                     // bAlternateSetting: alternate setting
                .bNumEndpoints              = LFH_U8(T_USB::EndpointCount()),                   // bNumEndpoints
                .bInterfaceClass            = LFH_U8(0xFF),                                     // bInterfaceClass: vendor specific
                .bInterfaceSubClass         = LFH_U8(0x00),                                     // bInterfaceSubClass
                .bInterfaceProtocol         = LFH_U8(0x00),                                     // nInterfaceProtocol
                .iInterface                 = LFH_U8(0x00),                                     // iInterface: string descriptor index
            },
            
                .epOut1Desc = {
                    .bLength                = LFH_U8(sizeof(USB::EndpointDescriptor)),          // bLength: Endpoint Descriptor size
                    .bDescriptorType        = LFH_U8(USB::DescriptorType::Endpoint),            // bDescriptorType: Endpoint
                    .bEndpointAddress       = LFH_U8(STM::Endpoints::DataOut),                  // bEndpointAddress
                    .bmAttributes           = LFH_U8(USB::EndpointAttributes::TransferBulk),    // bmAttributes: Bulk
                    .wMaxPacketSize         = LFH_U16(T_USB::MaxPacketSizeOut()),               // wMaxPacketSize
                    .bInterval              = LFH_U8(0x00),                                     // bInterval: ignore for Bulk transfer
                },
                
                .epIn1Desc = {
                    .bLength                = LFH_U8(sizeof(USB::EndpointDescriptor)),          // bLength: Endpoint Descriptor size
                    .bDescriptorType        = LFH_U8(USB::DescriptorType::Endpoint),            // bDescriptorType: Endpoint
                    .bEndpointAddress       = LFH_U8(STM::Endpoints::DataIn),                   // bEndpointAddress
                    .bmAttributes           = LFH_U8(USB::EndpointAttributes::TransferBulk),    // bmAttributes: Bulk
                    .wMaxPacketSize         = LFH_U16(T_USB::MaxPacketSizeIn()),                // wMaxPacketSize
                    .bInterval              = LFH_U8(0x00),                                     // bInterval: ignore for Bulk transfer
                },
    };
    
    len = sizeof(USBConfigDesc);
    return (const void*)&USBConfigDesc;
}

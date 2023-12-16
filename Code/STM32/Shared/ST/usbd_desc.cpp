#include "usbd_core.h"
#include "usbd_desc.h"

#define USBD_VID                        0
#define USBD_LANGID_STRING              1033
#define USBD_MANUFACTURER_STRING        "Toaster LLC"
#define USBD_PID_HS                     0
#define USBD_PRODUCT_STRING_HS          "Photon"
#define USBD_CONFIGURATION_STRING_HS    "DFU Config"
#define USBD_INTERFACE_STRING_HS        "DFU Interface"
#define USB_SIZ_BOS_DESC                0x0C

static void Get_SerialNum(void);
static void IntToUnicode(uint32_t value, uint8_t * pbuf, uint8_t len);

uint8_t * USBD_HS_DeviceDescriptor(USBD_SpeedTypeDef speed, uint16_t *length);
uint8_t * USBD_HS_LangIDStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length);
uint8_t * USBD_HS_ManufacturerStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length);
uint8_t * USBD_HS_ProductStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length);
uint8_t * USBD_HS_SerialStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length);
uint8_t * USBD_HS_ConfigStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length);
uint8_t * USBD_HS_InterfaceStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length);

#if (USBD_LPM_ENABLED == 1)
uint8_t * USBD_HS_USR_BOSDescriptor(USBD_SpeedTypeDef speed, uint16_t *length);
#endif

USBD_DescriptorsTypeDef HS_Desc =
{
  USBD_HS_DeviceDescriptor
, USBD_HS_LangIDStrDescriptor
, USBD_HS_ManufacturerStrDescriptor
, USBD_HS_ProductStrDescriptor
, USBD_HS_SerialStrDescriptor
, USBD_HS_ConfigStrDescriptor
, USBD_HS_InterfaceStrDescriptor
#if (USBD_LPM_ENABLED == 1)
, USBD_HS_USR_BOSDescriptor
#endif // (USBD_LPM_ENABLED == 1)
};

// USB standard device descriptor
uint8_t USBD_HS_DeviceDesc[USB_LEN_DEV_DESC] __attribute__((aligned(4))) =
{
    0x12,                           // bLength
    USB_DESC_TYPE_DEVICE,           // bDescriptorType
#if (USBD_LPM_ENABLED == 1)
    0x01, 0x02,                     // bcdUSB
                                    //   changed to USB version 2.01
                                    //   in order to support LPM L1 suspend
                                    //   resume test of USBCV3.0
#else
    0x00, 0x02,                     // bcdUSB
#endif // (USBD_LPM_ENABLED == 1)
    
    0x00,                           // bDeviceClass
    0x00,                           // bDeviceSubClass
    0x00,                           // bDeviceProtocol
    USB_MAX_EP0_SIZE,               // bMaxPacketSize
    LOBYTE(USBD_VID),               // idVendor
    HIBYTE(USBD_VID),               // idVendor
    LOBYTE(USBD_PID_HS),            // idProduct
    HIBYTE(USBD_PID_HS),            // idProduct
    0x00, 0x02,                     // bcdDevice rel. 2.00
    USBD_IDX_MFC_STR,               // Index of manufacturer  string
    USBD_IDX_PRODUCT_STR,           // Index of product string
    USBD_IDX_SERIAL_STR,            // Index of serial number string
    USBD_MAX_NUM_CONFIGURATION      // bNumConfigurations
};

// BOS descriptor
#if (USBD_LPM_ENABLED == 1)
uint8_t USBD_HS_BOSDesc[USB_SIZ_BOS_DESC] __attribute__((aligned(4))) =
{
  0x5,
  USB_DESC_TYPE_BOS,
  0xC,
  0x0,
  0x1,  // 1 device capability
  0x7,
  USB_DEVICE_CAPABITY_TYPE,
  0x2,
  0x2,  // LPM capability bit set
  0x0,
  0x0,
  0x0
};
#endif

// USB lang indentifier descriptor
uint8_t USBD_LangIDDesc[USB_LEN_LANGID_STR_DESC] __attribute__((aligned(4))) =
{
     USB_LEN_LANGID_STR_DESC,
     USB_DESC_TYPE_STRING,
     LOBYTE(USBD_LANGID_STRING),
     HIBYTE(USBD_LANGID_STRING)
};

// Internal string descriptor
uint8_t USBD_StrDesc[USBD_MAX_STR_DESC_SIZ] __attribute__((aligned(4)));

uint8_t USBD_StringSerial[USB_SIZ_STRING_SERIAL] __attribute__((aligned(4))) = {
  USB_SIZ_STRING_SERIAL,
  USB_DESC_TYPE_STRING,
};

// Return the device descriptor
uint8_t * USBD_HS_DeviceDescriptor(USBD_SpeedTypeDef speed, uint16_t *length)
{
  UNUSED(speed);
  *length = sizeof(USBD_HS_DeviceDesc);
  return USBD_HS_DeviceDesc;
}

// Return the LangID string descriptor
uint8_t * USBD_HS_LangIDStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length)
{
  UNUSED(speed);
  *length = sizeof(USBD_LangIDDesc);
  return USBD_LangIDDesc;
}

// Return the product string descriptor
uint8_t * USBD_HS_ProductStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length)
{
  if(speed == 0)
  {
    USBD_GetString((uint8_t *)USBD_PRODUCT_STRING_HS, USBD_StrDesc, length);
  }
  else
  {
    USBD_GetString((uint8_t *)USBD_PRODUCT_STRING_HS, USBD_StrDesc, length);
  }
  return USBD_StrDesc;
}

// Return the manufacturer string descriptor
uint8_t * USBD_HS_ManufacturerStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length)
{
  UNUSED(speed);
  USBD_GetString((uint8_t *)USBD_MANUFACTURER_STRING, USBD_StrDesc, length);
  return USBD_StrDesc;
}

// Return the serial number string descriptor
uint8_t * USBD_HS_SerialStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length)
{
  UNUSED(speed);
  *length = USB_SIZ_STRING_SERIAL;

  // Update the serial number string descriptor with the data from the unique ID
  Get_SerialNum();
  return (uint8_t *) USBD_StringSerial;
}

// Return the configuration string descriptor
uint8_t * USBD_HS_ConfigStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length)
{
  if(speed == USBD_SPEED_HIGH)
  {
    USBD_GetString((uint8_t *)USBD_CONFIGURATION_STRING_HS, USBD_StrDesc, length);
  }
  else
  {
    USBD_GetString((uint8_t *)USBD_CONFIGURATION_STRING_HS, USBD_StrDesc, length);
  }
  return USBD_StrDesc;
}

// Return the interface string descriptor
uint8_t * USBD_HS_InterfaceStrDescriptor(USBD_SpeedTypeDef speed, uint16_t *length)
{
  if(speed == 0)
  {
    USBD_GetString((uint8_t *)USBD_INTERFACE_STRING_HS, USBD_StrDesc, length);
  }
  else
  {
    USBD_GetString((uint8_t *)USBD_INTERFACE_STRING_HS, USBD_StrDesc, length);
  }
  return USBD_StrDesc;
}

#if (USBD_LPM_ENABLED == 1)
// Return the BOS descriptor
uint8_t * USBD_HS_USR_BOSDescriptor(USBD_SpeedTypeDef speed, uint16_t *length)
{
  UNUSED(speed);
  *length = sizeof(USBD_HS_BOSDesc);
  return (uint8_t*)USBD_HS_BOSDesc;
}
#endif

// Create the serial number string descriptor
static void Get_SerialNum(void)
{
  uint32_t deviceserial0, deviceserial1, deviceserial2;

  deviceserial0 = *(uint32_t *) DEVICE_ID1;
  deviceserial1 = *(uint32_t *) DEVICE_ID2;
  deviceserial2 = *(uint32_t *) DEVICE_ID3;

  deviceserial0 += deviceserial2;

  if (deviceserial0 != 0)
  {
    IntToUnicode(deviceserial0, &USBD_StringSerial[2], 8);
    IntToUnicode(deviceserial1, &USBD_StringSerial[18], 4);
  }
}

// Convert Hex 32Bits value into char
static void IntToUnicode(uint32_t value, uint8_t * pbuf, uint8_t len)
{
  uint8_t idx = 0;

  for (idx = 0; idx < len; idx++)
  {
    if (((value >> 28)) < 0xA)
    {
      pbuf[2 * idx] = (value >> 28) + '0';
    }
    else
    {
      pbuf[2 * idx] = (value >> 28) + 'A' - 10;
    }

    value = value << 4;

    pbuf[2 * idx + 1] = 0;
  }
}

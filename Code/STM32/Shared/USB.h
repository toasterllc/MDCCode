#pragma once
#include <initializer_list>
#include <optional>
#include "Code/Shared/Assert.h"
#include "stm32f7xx.h"
#include "usbd_def.h"
#include "usbd_core.h"
#include "usbd_desc.h"
#include "Code/Lib/Toastbox/USB.h"
#include "Code/Lib/Scheduler/Scheduler.h"

template <
typename T_Scheduler,   // T_Scheduler: scheduler
bool T_DMAEn,           // T_DMAEn: whether DMA is enabled
typename T_Config       // T_ConfigDesc: contains endpoints and configuration descriptor
>
class T_USB {
public:
    struct Cmd {
        const uint8_t* data;
        size_t len;
    };
    
private:
    enum class _EndpointStage : uint8_t {
        Ready,
        Busy,
        Done,
        
        Reset,
        ResetZLP1,
        ResetZLP2,
        ResetSentinel,
    };
    
    struct _EndpointState {
        _EndpointStage stage = _EndpointStage::Ready;
        size_t len = 0;
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
    
    // Types
    enum class State : uint8_t {
        Disconnected,
        Connecting,
        Connected,
    };
    
    // Initialization
    static void Init() {
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
            .Setup                          = Fwd1(Setup, const Toastbox::USB::SetupRequest&),
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
        
        T_Scheduler::Ctx(ep);
        T_Scheduler::Wait([] { return _EndpointReady(T_Scheduler::template Ctx<uint8_t>()); });
    }
    
    static void EndpointsReset() {
        Toastbox::IntState ints(false);
        for (uint8_t ep : T_Config::Endpoints) {
            _EndpointReset(ep);
        }
        T_Scheduler::Wait([] { return _EndpointsReady(); });
    }
    
    
    
    
    
        static void USBD_GetDescriptor(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
        {
          uint16_t len = 0U;
          uint8_t *pbuf = NULL;
          uint8_t err = 0U;

          switch (req.wValue >> 8)
          {
        #if ((USBD_LPM_ENABLED == 1U) || (USBD_CLASS_BOS_ENABLED == 1U))
          case USB_DESC_TYPE_BOS:
            if (pdev->pDesc->GetBOSDescriptor != NULL)
            {
              pbuf = pdev->pDesc->GetBOSDescriptor(pdev->dev_speed, &len);
            }
            else
            {
              _CmdAccept(false);
              err++;
            }
            break;
        #endif
          case USB_DESC_TYPE_DEVICE:
            pbuf = pdev->pDesc->GetDeviceDescriptor(pdev->dev_speed, &len);
            break;

          case USB_DESC_TYPE_CONFIGURATION:
            if (pdev->dev_speed == USBD_SPEED_HIGH)
            {
              pbuf = pdev->pClass->GetHSConfigDescriptor(pdev, &len);
            }
            else
            {
              pbuf = pdev->pClass->GetFSConfigDescriptor(pdev, &len);
            }
            break;

          case USB_DESC_TYPE_STRING:
            switch ((uint8_t)(req.wValue))
            {
            case USBD_IDX_LANGID_STR:
              if (pdev->pDesc->GetLangIDStrDescriptor != NULL)
              {
                pbuf = pdev->pDesc->GetLangIDStrDescriptor(pdev->dev_speed, &len);
              }
              else
              {
                _CmdAccept(false);
                err++;
              }
              break;

            case USBD_IDX_MFC_STR:
              if (pdev->pDesc->GetManufacturerStrDescriptor != NULL)
              {
                pbuf = pdev->pDesc->GetManufacturerStrDescriptor(pdev->dev_speed, &len);
              }
              else
              {
                _CmdAccept(false);
                err++;
              }
              break;

            case USBD_IDX_PRODUCT_STR:
              if (pdev->pDesc->GetProductStrDescriptor != NULL)
              {
                pbuf = pdev->pDesc->GetProductStrDescriptor(pdev->dev_speed, &len);
              }
              else
              {
                _CmdAccept(false);
                err++;
              }
              break;

            case USBD_IDX_SERIAL_STR:
              if (pdev->pDesc->GetSerialStrDescriptor != NULL)
              {
                pbuf = pdev->pDesc->GetSerialStrDescriptor(pdev->dev_speed, &len);
              }
              else
              {
                _CmdAccept(false);
                err++;
              }
              break;

            case USBD_IDX_CONFIG_STR:
              if (pdev->pDesc->GetConfigurationStrDescriptor != NULL)
              {
                pbuf = pdev->pDesc->GetConfigurationStrDescriptor(pdev->dev_speed, &len);
              }
              else
              {
                _CmdAccept(false);
                err++;
              }
              break;

            case USBD_IDX_INTERFACE_STR:
              if (pdev->pDesc->GetInterfaceStrDescriptor != NULL)
              {
                pbuf = pdev->pDesc->GetInterfaceStrDescriptor(pdev->dev_speed, &len);
              }
              else
              {
                _CmdAccept(false);
                err++;
              }
              break;

            default:
              if (pdev->pClass->GetUsrStrDescriptor != NULL)
              {
                pbuf = pdev->pClass->GetUsrStrDescriptor(pdev, (req.wValue), &len);
              }
              else
              {
                _CmdAccept(false);
                err++;
              }
              break;
            }
            break;

          default:
            _CmdAccept(false);
            err++;
            break;
          }

          if (err != 0U)
          {
            return;
          }
          else
          {
            if (req.wLength != 0U)
            {
              if (len != 0U)
              {
                len = MIN(len, req.wLength);
                (void)USBD_CtlSendData(pdev, pbuf, len);
              }
              else
              {
                _CmdAccept(false);
              }
            }
            else
            {
              _CmdAccept(true);
            }
          }
        }

        /**
        * @brief  USBD_SetAddress
        *         Set device address
        * @param  pdev: device instance
        * @param  req: usb request
        * @retval status
        */
        static void USBD_SetAddress(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
        {
          uint8_t  dev_addr;

          if ((req.wIndex == 0U) && (req.wLength == 0U) && (req.wValue < 128U))
          {
            dev_addr = (uint8_t)(req.wValue) & 0x7FU;

            if (pdev->dev_state == USBD_STATE_CONFIGURED)
            {
              _CmdAccept(false);
            }
            else
            {
              pdev->dev_address = dev_addr;
              (void)USBD_LL_SetUSBAddress(pdev, dev_addr);
              _CmdAccept(true);

              if (dev_addr != 0U)
              {
                pdev->dev_state = USBD_STATE_ADDRESSED;
              }
              else
              {
                pdev->dev_state = USBD_STATE_DEFAULT;
              }
            }
          }
          else
          {
            _CmdAccept(false);
          }
        }

        /**
        * @brief  USBD_SetConfig
        *         Handle Set device configuration request
        * @param  pdev: device instance
        * @param  req: usb request
        * @retval status
        */
        static USBD_StatusTypeDef USBD_SetConfig(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
        {
          USBD_StatusTypeDef ret = USBD_OK;
          static uint8_t cfgidx;

          cfgidx = (uint8_t)(req.wValue);

          if (cfgidx > USBD_MAX_NUM_CONFIGURATION)
          {
            _CmdAccept(false);
            return USBD_FAIL;
          }

          switch (pdev->dev_state)
          {
          case USBD_STATE_ADDRESSED:
            if (cfgidx != 0U)
            {
              pdev->dev_config = cfgidx;

              ret = USBD_SetClassConfig(pdev, cfgidx);

              if (ret != USBD_OK)
              {
                _CmdAccept(false);
              }
              else
              {
                _CmdAccept(true);
                pdev->dev_state = USBD_STATE_CONFIGURED;
              }
            }
            else
            {
              _CmdAccept(true);
            }
            break;

          case USBD_STATE_CONFIGURED:
            if (cfgidx == 0U)
            {
              pdev->dev_state = USBD_STATE_ADDRESSED;
              pdev->dev_config = cfgidx;
              (void)USBD_ClrClassConfig(pdev, cfgidx);
              _CmdAccept(true);
            }
            else if (cfgidx != pdev->dev_config)
            {
              /* Clear old configuration */
              (void)USBD_ClrClassConfig(pdev, (uint8_t)pdev->dev_config);

              /* set new configuration */
              pdev->dev_config = cfgidx;

              ret = USBD_SetClassConfig(pdev, cfgidx);

              if (ret != USBD_OK)
              {
                _CmdAccept(false);
                (void)USBD_ClrClassConfig(pdev, (uint8_t)pdev->dev_config);
                pdev->dev_state = USBD_STATE_ADDRESSED;
              }
              else
              {
                _CmdAccept(true);
              }
            }
            else
            {
              _CmdAccept(true);
            }
            break;

          default:
            _CmdAccept(false);
            (void)USBD_ClrClassConfig(pdev, cfgidx);
            ret = USBD_FAIL;
            break;
          }

          return ret;
        }

        /**
        * @brief  USBD_GetConfig
        *         Handle Get device configuration request
        * @param  pdev: device instance
        * @param  req: usb request
        * @retval status
        */
        static void USBD_GetConfig(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
        {
          if (req.wLength != 1U)
          {
            _CmdAccept(false);
          }
          else
          {
            switch (pdev->dev_state)
            {
            case USBD_STATE_DEFAULT:
            case USBD_STATE_ADDRESSED:
              pdev->dev_default_config = 0U;
              (void)USBD_CtlSendData(pdev, (uint8_t *)&pdev->dev_default_config, 1U);
              break;

            case USBD_STATE_CONFIGURED:
              (void)USBD_CtlSendData(pdev, (uint8_t *)&pdev->dev_config, 1U);
              break;

            default:
              _CmdAccept(false);
              break;
            }
          }
        }

        /**
        * @brief  USBD_GetStatus
        *         Handle Get Status request
        * @param  pdev: device instance
        * @param  req: usb request
        * @retval status
        */
        static void USBD_GetStatus(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
        {
          switch (pdev->dev_state)
          {
          case USBD_STATE_DEFAULT:
          case USBD_STATE_ADDRESSED:
          case USBD_STATE_CONFIGURED:
            if (req.wLength != 0x2U)
            {
              _CmdAccept(false);
              break;
            }

        #if (USBD_SELF_POWERED == 1U)
            pdev->dev_config_status = USB_CONFIG_SELF_POWERED;
        #else
            pdev->dev_config_status = 0U;
        #endif

            if (pdev->dev_remote_wakeup != 0U)
            {
              pdev->dev_config_status |= USB_CONFIG_REMOTE_WAKEUP;
            }

            (void)USBD_CtlSendData(pdev, (uint8_t *)&pdev->dev_config_status, 2U);
            break;

          default:
            _CmdAccept(false);
            break;
          }
        }


        /**
        * @brief  USBD_SetFeature
        *         Handle Set device feature request
        * @param  pdev: device instance
        * @param  req: usb request
        * @retval status
        */
        static void USBD_SetFeature(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
        {
          if (req.wValue == USB_FEATURE_REMOTE_WAKEUP)
          {
            pdev->dev_remote_wakeup = 1U;
            _CmdAccept(true);
          }
        }


        /**
        * @brief  USBD_ClrFeature
        *         Handle clear device feature request
        * @param  pdev: device instance
        * @param  req: usb request
        * @retval status
        */
        static void USBD_ClrFeature(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
        {
          switch (pdev->dev_state)
          {
            case USBD_STATE_DEFAULT:
            case USBD_STATE_ADDRESSED:
            case USBD_STATE_CONFIGURED:
              if (req.wValue == USB_FEATURE_REMOTE_WAKEUP)
              {
                pdev->dev_remote_wakeup = 0U;
                _CmdAccept(true);
              }
              break;

            default:
              _CmdAccept(false);
              break;
          }
        }

//        static void USBD_CtlError(USBD_HandleTypeDef *pdev)
//        {
//          (void)USBD_LL_StallEP(pdev, 0x80U);
//          (void)USBD_LL_StallEP(pdev, 0U);
//        }


        /**
          * @brief  USBD_GetLen
          *         return the string length
           * @param  buf : pointer to the ascii string buffer
          * @retval string length
          */
        static uint8_t USBD_GetLen(uint8_t *buf)
        {
          uint8_t  len = 0U;
          uint8_t *pbuff = buf;

          while (*pbuff != (uint8_t)'\0')
          {
            len++;
            pbuff++;
          }

          return len;
        }

        /**
          * @brief  USBD_GetString
          *         Convert Ascii string into unicode one
          * @param  desc : descriptor buffer
          * @param  unicode : Formatted string buffer (unicode)
          * @param  len : descriptor length
          * @retval None
          */
        static void USBD_GetString(uint8_t *desc, uint8_t *unicode, uint16_t *len)
        {
          uint8_t idx = 0U;
          uint8_t *pdesc;

          if (desc == NULL)
          {
            return;
          }

          pdesc = desc;
          *len = ((uint16_t)USBD_GetLen(pdesc) * 2U) + 2U;

          unicode[idx] = *(uint8_t *)len;
          idx++;
          unicode[idx] = USB_DESC_TYPE_STRING;
          idx++;

          while (*pdesc != (uint8_t)'\0')
          {
            unicode[idx] = *pdesc;
            pdesc++;
            idx++;

            unicode[idx] = 0U;
            idx++;
          }
        }

    
    
    
    
    static USBD_StatusTypeDef USBD_StdDevReq(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
    {
      USBD_StatusTypeDef ret = USBD_OK;

      switch (req.bmRequestType & USB_REQ_TYPE_MASK)
      {
      case USB_REQ_TYPE_CLASS:
      case USB_REQ_TYPE_VENDOR:
        _CmdAccept(false);
        break;

      case USB_REQ_TYPE_STANDARD:
        switch (req.bRequest)
        {
        case USB_REQ_GET_DESCRIPTOR:
          USBD_GetDescriptor(pdev, req);
          break;

        case USB_REQ_SET_ADDRESS:
          USBD_SetAddress(pdev, req);
          break;

        case USB_REQ_SET_CONFIGURATION:
          ret = USBD_SetConfig(pdev, req);
          break;

        case USB_REQ_GET_CONFIGURATION:
          USBD_GetConfig(pdev, req);
          break;

        case USB_REQ_GET_STATUS:
          USBD_GetStatus(pdev, req);
          break;

        case USB_REQ_SET_FEATURE:
          USBD_SetFeature(pdev, req);
          break;

        case USB_REQ_CLEAR_FEATURE:
          USBD_ClrFeature(pdev, req);
          break;

        default:
          _CmdAccept(false);
          break;
        }
        break;

      default:
        _CmdAccept(false);
        break;
      }

      return ret;
    }

    static USBD_StatusTypeDef USBD_StdItfReq(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
    {
      USBD_StatusTypeDef ret = USBD_OK;

      switch (req.bmRequestType & USB_REQ_TYPE_MASK)
      {
      case USB_REQ_TYPE_CLASS:
      case USB_REQ_TYPE_VENDOR:
      case USB_REQ_TYPE_STANDARD:
        switch (pdev->dev_state)
        {
        case USBD_STATE_DEFAULT:
        case USBD_STATE_ADDRESSED:
        case USBD_STATE_CONFIGURED:

          if (LOBYTE(req.wIndex) <= USBD_MAX_NUM_INTERFACES)
          {
            ret = (USBD_StatusTypeDef)pdev->pClass->Setup(pdev, req);

            if ((req.wLength == 0U) && (ret == USBD_OK))
            {
                _CmdAccept(true);
            }
          }
          else
          {
            _CmdAccept(false);
          }
          break;

        default:
          _CmdAccept(false);
          break;
        }
        break;

      default:
        _CmdAccept(false);
        break;
      }

      return ret;
    }

    static USBD_StatusTypeDef USBD_StdEPReq(USBD_HandleTypeDef *pdev, const Toastbox::USB::SetupRequest& req)
    {
      USBD_EndpointTypeDef *pep;
      uint8_t ep_addr;
      USBD_StatusTypeDef ret = USBD_OK;
      ep_addr = LOBYTE(req.wIndex);

      switch (req.bmRequestType & USB_REQ_TYPE_MASK)
      {
      case USB_REQ_TYPE_CLASS:
      case USB_REQ_TYPE_VENDOR:
        ret = (USBD_StatusTypeDef)pdev->pClass->Setup(pdev, req);
        break;

      case USB_REQ_TYPE_STANDARD:
        switch (req.bRequest)
        {
        case USB_REQ_SET_FEATURE:
          switch (pdev->dev_state)
          {
          case USBD_STATE_ADDRESSED:
            if ((ep_addr != 0x00U) && (ep_addr != 0x80U))
            {
              (void)USBD_LL_StallEP(pdev, ep_addr);
              (void)USBD_LL_StallEP(pdev, 0x80U);
            }
            else
            {
              _CmdAccept(false);
            }
            break;

          case USBD_STATE_CONFIGURED:
            if (req.wValue == USB_FEATURE_EP_HALT)
            {
              if ((ep_addr != 0x00U) && (ep_addr != 0x80U) && (req.wLength == 0x00U))
              {
                (void)USBD_LL_StallEP(pdev, ep_addr);
              }
            }
            _CmdAccept(true);
            break;

          default:
            _CmdAccept(false);
            break;
          }
          break;

        case USB_REQ_CLEAR_FEATURE:

          switch (pdev->dev_state)
          {
          case USBD_STATE_ADDRESSED:
            if ((ep_addr != 0x00U) && (ep_addr != 0x80U))
            {
              (void)USBD_LL_StallEP(pdev, ep_addr);
              (void)USBD_LL_StallEP(pdev, 0x80U);
            }
            else
            {
              _CmdAccept(false);
            }
            break;

          case USBD_STATE_CONFIGURED:
            if (req.wValue == USB_FEATURE_EP_HALT)
            {
              if ((ep_addr & 0x7FU) != 0x00U)
              {
                (void)USBD_LL_ClearStallEP(pdev, ep_addr);
              }
              _CmdAccept(true);
              (USBD_StatusTypeDef)pdev->pClass->Setup(pdev, req);
            }
            break;

          default:
            _CmdAccept(false);
            break;
          }
          break;

        case USB_REQ_GET_STATUS:
          switch (pdev->dev_state)
          {
          case USBD_STATE_ADDRESSED:
            if ((ep_addr != 0x00U) && (ep_addr != 0x80U))
            {
              _CmdAccept(false);
              break;
            }
            pep = ((ep_addr & 0x80U) == 0x80U) ? &pdev->ep_in[ep_addr & 0x7FU] : \
                  &pdev->ep_out[ep_addr & 0x7FU];

            pep->status = 0x0000U;

            (void)USBD_CtlSendData(pdev, (uint8_t *)&pep->status, 2U);
            break;

          case USBD_STATE_CONFIGURED:
            if ((ep_addr & 0x80U) == 0x80U)
            {
              if (pdev->ep_in[ep_addr & 0xFU].is_used == 0U)
              {
                _CmdAccept(false);
                break;
              }
            }
            else
            {
              if (pdev->ep_out[ep_addr & 0xFU].is_used == 0U)
              {
                _CmdAccept(false);
                break;
              }
            }

            pep = ((ep_addr & 0x80U) == 0x80U) ? &pdev->ep_in[ep_addr & 0x7FU] : \
                  &pdev->ep_out[ep_addr & 0x7FU];

              if ((ep_addr == 0x00U) || (ep_addr == 0x80U))
              {
                pep->status = 0x0000U;
              }
              else if (USBD_LL_IsStallEP(pdev, ep_addr) != 0U)
              {
                pep->status = 0x0001U;
              }
              else
              {
                pep->status = 0x0000U;
              }

              (void)USBD_CtlSendData(pdev, (uint8_t *)&pep->status, 2U);
              break;

          default:
            _CmdAccept(false);
            break;
          }
          break;

        default:
          _CmdAccept(false);
          break;
        }
        break;

      default:
        _CmdAccept(false);
        break;
      }

      return ret;
    }

    static USBD_StatusTypeDef _SetupRequestHandle(const Toastbox::USB::SetupRequest& req) {
        switch (req.bmRequestType & 0x1FU) {
        case USB_REQ_RECIPIENT_DEVICE:
            return USBD_StdDevReq(&_Device, req);
            break;
        case USB_REQ_RECIPIENT_INTERFACE:
            return USBD_StdItfReq(&_Device, req);
            break;
        case USB_REQ_RECIPIENT_ENDPOINT:
            return USBD_StdEPReq(&_Device, req);
            break;
        default:
            return USBD_LL_StallEP(&_Device, (req.bmRequestType & 0x80U));
            break;
      }
    }
    
    static Toastbox::USB::SetupRequest SetupRequestRecv() {
        for (;;) {
            Toastbox::IntState ints(false);
            
            // Wait until we're in the Connecting state
            {
                T_Scheduler::Wait([] { return _State == State::Connecting || _State == State::Connected; });
                if (_State == State::Connecting) {
                    // Update our state
                    _State = State::Connected;
                    _SetupRequest = std::nullopt;
                }
            }
            
            // Wait for a command
            for (;;) {
                // Wait for a new command to arrive, or for our state to change
                T_Scheduler::Wait([] { return _SetupRequest || _State!=State::Connected; });
                
                // If we're no longer connected, bail and wait to be connected again
                if (_State != State::Connected) break;
                
                // Handle the setup request
                _SetupRequestHandle(*_SetupRequest);
                
                // Consume the command
                _SetupRequest = std::nullopt;
            }
        }
    }
    
    static void CmdAccept(bool accept) {
        Toastbox::IntState ints(false);
        // Short-circuit if we're not Connected
        if (_State != State::Connected) return;
        _CmdAccept(accept);
    }
    
    static std::optional<size_t> Recv(uint8_t ep, void* data, size_t len) {
        Assert(EndpointOut(ep));
        _EndpointState& eps = _EndpointStateGet(ep);
        
        Toastbox::IntState ints(false);
        if (_State != State::Connected) return std::nullopt; // Short-circuit if we're not Connected
        
        Assert(_Ready(eps));
        _AdvanceStateOut(ep);
        
        const USBD_StatusTypeDef us = USBD_LL_PrepareReceive(&_Device, ep, (uint8_t*)data, len);
        Assert(us == USBD_OK);
        
        _WaitState ws = { .ep = ep };
        T_Scheduler::Ctx(&ws); // Set current task's context, which we'll retrieve from the Wait() lambda
        T_Scheduler::Wait([] { return _WaitRecv(*T_Scheduler::template Ctx<_WaitState*>()); });
        if (!ws.ok) return std::nullopt;
        return ws.len;
    }
    
    static bool Send(uint8_t ep, const void* data, size_t len) {
        Assert(EndpointIn(ep));
        _EndpointState& eps = _EndpointStateGet(ep);
        
        Toastbox::IntState ints(false);
        if (_State != State::Connected) return false; // Short-circuit if we're not Connected
        
        Assert(_Ready(eps));
        _AdvanceStateIn(ep);
        
        const USBD_StatusTypeDef us = USBD_LL_Transmit(&_Device, ep, (uint8_t*)data, len);
        Assert(us == USBD_OK);
        
        _WaitState ws = { .ep = ep };
        T_Scheduler::Ctx(&ws); // Set current task's context, which we'll retrieve from the Wait() lambda
        T_Scheduler::Wait([] { return _WaitSend(*T_Scheduler::template Ctx<_WaitState*>()); });
        return ws.ok;
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
            
            } else {
                USBD_LL_OpenEP(&_Device, ep, USBD_EP_TYPE_BULK, MaxPacketSizeIn());
                _Device.ep_in[EndpointIdx(ep)].is_used = 1U;
            }
            
            // Reset endpoint state
            _EndpointStateGet(ep) = {};
        }
        
        _State = State::Connecting;
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_DeInit(uint8_t cfgidx) {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_Suspend() {
        _State = State::Disconnected;
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_Resume() {
        _State = State::Connected;
        return (uint8_t)USBD_OK;
    }
    
//  USBD_StatusTypeDef ret;
//
//  USBD_ParseSetupRequest(&pdev->request, psetup);
//
//  pdev->ep0_state = USBD_EP0_SETUP;
//
//  pdev->ep0_data_len = pdev->request.wLength;
//
//  switch (pdev->request.bmRequestType & 0x1FU)
//  {
//    case USB_REQ_RECIPIENT_DEVICE:
//      ret = USBD_StdDevReq(pdev, &pdev->request);
//      break;
//
//    case USB_REQ_RECIPIENT_INTERFACE:
//      ret = USBD_StdItfReq(pdev, &pdev->request);
//      break;
//
//    case USB_REQ_RECIPIENT_ENDPOINT:
//      ret = USBD_StdEPReq(pdev, &pdev->request);
//      break;
//
//    default:
//      ret = USBD_LL_StallEP(pdev, (pdev->request.bmRequestType & 0x80U));
//      break;
//  }
//
//  return ret;
    
    static uint8_t _USBD_Setup(const Toastbox::USB::SetupRequest& req) {
        if (_SetupRequest) {
            _CmdAccept(false);
            return (uint8_t)USBD_FAIL;
        }
        
        _SetupRequest = req;
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_EP0_TxSent() {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_EP0_RxReady() {
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_DataIn(uint8_t epidx) {
        const uint8_t ep = Toastbox::USB::Endpoint::DirectionIn | epidx;
        // Sanity-check the endpoint state
        _EndpointState& eps = _EndpointStateGet(ep);
        Assert(
            eps.stage == _EndpointStage::ResetZLP1     ||
            eps.stage == _EndpointStage::ResetZLP2     ||
            eps.stage == _EndpointStage::ResetSentinel ||
            eps.stage == _EndpointStage::Busy
        );
        _AdvanceStateIn(ep);
        return (uint8_t)USBD_OK;
    }
    
    static uint8_t _USBD_DataOut(uint8_t epidx) {
        const uint8_t ep = Toastbox::USB::Endpoint::DirectionOut | epidx;
        _EndpointState& eps = _EndpointStateGet(ep);
        // Sanity-check the endpoint state
        Assert(
            eps.stage == _EndpointStage::ResetZLP1     ||
            eps.stage == _EndpointStage::ResetZLP2     ||
            eps.stage == _EndpointStage::ResetSentinel ||
            eps.stage == _EndpointStage::Busy
        );
        _AdvanceStateOut(ep);
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
    
    // Ints must be disabled
    static void _CmdAccept(bool accept) {
        if (accept) {
//            USBD_CtlSendStatus(&_Device);
            
            USBD_LL_TransmitZeroLen(&_Device, 0U);
        
        } else {
//            USBD_CtlError(&_Device);
            
            USBD_LL_StallEP(&_Device, 0x80);
            USBD_LL_StallEP(&_Device, 0x00);
        }
    }
    
    struct _WaitState {
        const uint8_t ep = 0;
        bool ok = false;
        size_t len = 0;
    };
    
    static bool _WaitRecv(_WaitState& ws) {
        // Short-circuit if we're not Connected
        if (_State != State::Connected) return true; // Done, failed
        
        const _EndpointState& eps = _EndpointStateGet(ws.ep);
        switch (eps.stage) {
        // Still waiting for completion
        case _EndpointStage::Busy:
            return false;
        // Done, success
        case _EndpointStage::Done:
            ws.ok = true;
            ws.len = eps.len;
            _AdvanceStateOut(ws.ep);
            return true;
        // Done, failed
        default:
            return true;
        }
    }
    
    static bool _WaitSend(_WaitState& ws) {
        // Short-circuit if we're not Connected
        if (_State != State::Connected) return true; // Done, failed
        
        const _EndpointState& eps = _EndpointStateGet(ws.ep);
        switch (eps.stage) {
        // Still waiting for completion
        case _EndpointStage::Busy:
            return false;
        // Done, success
        case _EndpointStage::Done:
            ws.ok = true;
            _AdvanceStateIn(ws.ep);
            return true;
        // Done, failed
        default:
            return true;
        }
    }
    
    // Ints must be disabled
    static void _EndpointReset(uint8_t ep) {
        if (_State != State::Connected) return; // Short-circuit if we're not Connected
        _EndpointState& eps = _EndpointStateGet(ep);
        eps.needsReset = true;
        if (_Ready(eps)) {
            if (EndpointOut(ep)) {
                _AdvanceStateOut(ep);
            } else {
                _AdvanceStateIn(ep);
            }
        }
    }
    
    // Ints must be disabled
    static bool _EndpointReady(uint8_t ep) {
        return _Ready(_EndpointStateGet(ep));
    }
    
    // Ints must be disabled
    static bool _EndpointsReady() {
        for (uint8_t ep : T_Config::Endpoints) {
            if (!_EndpointReady(ep)) return false;
        }
        return true;
    }
    
    // Ints must be disabled
    static bool _Ready(const _EndpointState& eps) {
        return eps.stage==_EndpointStage::Ready;
    }
    
    // Ints must be disabled
    static void _AdvanceStateOut(uint8_t ep) {
        _EndpointState& eps = _EndpointStateGet(ep);
        if (eps.needsReset) {
            eps.stage = _EndpointStage::Reset;
            eps.needsReset = false;
        }
        
        eps.len = USBD_LL_GetRxDataSize(&_Device, ep);
        
        // State transitions
        switch (eps.stage) {
        case _EndpointStage::Ready:     eps.stage = _EndpointStage::Busy; break;
        case _EndpointStage::Busy:      eps.stage = _EndpointStage::Done; break;
        case _EndpointStage::Done:      eps.stage = _EndpointStage::Ready; break;
        case _EndpointStage::Reset:     eps.stage = _EndpointStage::ResetZLP1; break;
        case _EndpointStage::ResetZLP1:
            // Only advance if we received a ZLP
            if (eps.len == 0) eps.stage = _EndpointStage::ResetSentinel;
            break;
        case _EndpointStage::ResetSentinel:
            // Only advance if we received the sentinel
            if (eps.len == sizeof(_ResetSentinel)) eps.stage = _EndpointStage::Ready;
            break;
        default:
            Assert(false);
        }
        
        // State actions
        switch (eps.stage) {
        case _EndpointStage::ResetZLP1:
        case _EndpointStage::ResetSentinel:
            USBD_LL_PrepareReceive(&_Device, ep, (uint8_t*)_DevNullAddr, MaxPacketSizeBulk);
            break;
        default:
            break;
        }
    }
    
    // Ints must be disabled
    static void _AdvanceStateIn(uint8_t ep) {
        _EndpointState& eps = _EndpointStateGet(ep);
        if (eps.needsReset) {
            eps.stage = _EndpointStage::Reset;
            eps.needsReset = false;
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
        switch (eps.stage) {
        case _EndpointStage::Ready:         eps.stage = _EndpointStage::Busy;          break;
        case _EndpointStage::Busy:          eps.stage = _EndpointStage::Done;          break;
        case _EndpointStage::Done:          eps.stage = _EndpointStage::Ready;         break;
        case _EndpointStage::Reset:         eps.stage = _EndpointStage::ResetZLP1;     break;
        case _EndpointStage::ResetZLP1:     eps.stage = _EndpointStage::ResetZLP2;     break;
        case _EndpointStage::ResetZLP2:     eps.stage = _EndpointStage::ResetSentinel; break;
        case _EndpointStage::ResetSentinel: eps.stage = _EndpointStage::Ready;         break;
        default:                            Assert(false);
        }
        
        // State actions
        switch (eps.stage) {
        case _EndpointStage::ResetZLP1:
        case _EndpointStage::ResetZLP2:
            USBD_LL_TransmitZeroLen(&_Device, ep);
            break;
        case _EndpointStage::ResetSentinel:
            USBD_LL_Transmit(&_Device, ep, (uint8_t*)&_ResetSentinel, sizeof(_ResetSentinel));
            break;
        default:
            break;
        }
    }
    
    static _EndpointState& _EndpointStateGet(uint8_t ep) {
        if (EndpointOut(ep)) {
            return _EndpointsOut[EndpointIdx(ep)-1];
        } else {
            return _EndpointsIn[EndpointIdx(ep)-1];
        }
    }
    
private:
    alignas(void*) // Aligned to send via USB
    static const inline uint8_t _ResetSentinel = 0;
    
    // _DevNullAddr: address that throw-away data can be written to.
    // This must be a region that a packet can be written to without causing
    // side-effects. We don't want to reserve actual RAM for this because it'd
    // just be wasted.
    // We're currently using the flash base address, so that the writes will be
    // ignored as long as the flash isn't unlocked.
    static constexpr uint32_t _DevNullAddr = 0x08000000;
    
//    alignas(void*) // Aligned to receive via USB
//    static inline uint8_t _CmdRecvBuf[MaxPacketSizeCtrl];
//    
//    static inline std::optional<size_t> _CmdRecvLen;
    
    static inline std::optional<Toastbox::USB::SetupRequest> _SetupRequest;
    
    static inline _EndpointState _EndpointsOut[EndpointCountOut()] = {};
    static inline _EndpointState _EndpointsIn[EndpointCountIn()] = {};
    static inline USBD_HandleTypeDef _Device;
    static inline PCD_HandleTypeDef _PCD;
    static inline State _State = State::Disconnected;
};

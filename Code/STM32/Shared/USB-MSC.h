#define BOT_GET_MAX_LUN     0xFE
#define BOT_RESET           0xFF

static void USBD_MSC_Setup(const Toastbox::USB::SetupRequest& req) {
    switch (req.bmRequestType & Toastbox::USB::RequestType::TypeMask) {
    case USB_REQ_TYPE_CLASS:
        switch (req.bRequest) {
        case BOT_GET_MAX_LUN:
            if (!req.wValue && req.wLength==1 && (req.bmRequestType & 0x80)) {
                static uint8_t maxLun = 0;
                Send(0x80, (uint8_t*)&maxLun, sizeof(maxLun));
                Recv(0x00, nullptr, 0);
                return;
            }
            break;
        
        case BOT_RESET:
            AssertLED(false);
            break;
//            if ((req.wValue  == 0U) && (req.wLength == 0U) && ((req.bmRequestType & 0x80U) != 0x80U)) {
//                return MSC_BOT_Reset(pdev);
//            }
//            break;
        }
    }
    AssertLED(false);
    _CmdAccept(false);
}

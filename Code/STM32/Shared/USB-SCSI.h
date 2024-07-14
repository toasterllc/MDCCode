static void SCSI_TestUnitReady(uint8_t lun, uint8_t *params) {
}

static void SCSI_Inquiry(uint8_t lun, uint8_t *params) {
    if ((params[1] & 0x01U) != 0U) /* Evpd is set */
    {
        if (params[2] == 0U) /* Request for Supported Vital Product Data Pages*/
        {
            toaster_printf("SCSI_Inquiry-Page00\n");
            
            alignas(void*)
            static const uint8_t MSC_Page00_Inquiry_Data[] = {
                0x00,
                0x00,
                0x00,
                0x02,
                0x00,
                0x80,
            };
            
            Send(0x81, MSC_Page00_Inquiry_Data, sizeof(MSC_Page00_Inquiry_Data));
        }
        else if (params[2] == 0x80U) /* Request for VPD page 0x80 Unit Serial Number */
        {
            toaster_printf("SCSI_Inquiry-Page80\n");
            
            alignas(void*)
            static const uint8_t MSC_Page80_Inquiry_Data[] = {
                0x00,
                0x80,
                0x00,
                0x08,
                0x20,     /* Put Product Serial number */
                0x20,
                0x20,
                0x20,
             };
            
            Send(0x81, MSC_Page80_Inquiry_Data, sizeof(MSC_Page80_Inquiry_Data));
        }
        else /* Request Not supported */
        {
            AssertLED(false);
        }
    }
    else
    {
        static constexpr size_t STANDARD_INQUIRY_DATA_LEN = 0x24;
        
        toaster_printf("SCSI_Inquiry-Standard\n");
        
        alignas(void*)
        static const uint8_t STORAGE_Inquirydata_HS[] = {
            0x00,
            0x80,
            0x02,
            0x02,
            (STANDARD_INQUIRY_DATA_LEN - 5),
            0x00,
            0x00,
            0x00,
            'S', 'T', 'M', ' ', ' ', ' ', ' ', ' ',
            'P', 'r', 'o', 'd', 'u', 'c', 't', ' ',
            ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
            '0', '.', '0' ,'1',
        };
        static_assert(sizeof(STORAGE_Inquirydata_HS) == STANDARD_INQUIRY_DATA_LEN);
        const size_t len = std::min((size_t)params[4], sizeof(STORAGE_Inquirydata_HS));
        Send(0x81, STORAGE_Inquirydata_HS, len);
    }
}

static void SCSI_ReadCapacity10(uint8_t lun, uint8_t *params) {
    
//    UNUSED(params);
//    int8_t ret;
//    USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;
//
//    ret = ((USBD_StorageTypeDef *)pdev->pUserData)->GetCapacity(lun, &hmsc->scsi_blk_nbr, &hmsc->scsi_blk_size);
//
//    if ((ret != 0) || (hmsc->scsi_medium_state == SCSI_MEDIUM_EJECTED))
//    {
//    SCSI_SenseCode(pdev, lun, NOT_READY, MEDIUM_NOT_PRESENT);
//    return -1;
//    }
//
//
//    hmsc->bot_data[0] = (uint8_t)((hmsc->scsi_blk_nbr - 1U) >> 24);
//    hmsc->bot_data[1] = (uint8_t)((hmsc->scsi_blk_nbr - 1U) >> 16);
//    hmsc->bot_data[2] = (uint8_t)((hmsc->scsi_blk_nbr - 1U) >>  8);
//    hmsc->bot_data[3] = (uint8_t)(hmsc->scsi_blk_nbr - 1U);
//
//    hmsc->bot_data[4] = (uint8_t)(hmsc->scsi_blk_size >>  24);
//    hmsc->bot_data[5] = (uint8_t)(hmsc->scsi_blk_size >>  16);
//    hmsc->bot_data[6] = (uint8_t)(hmsc->scsi_blk_size >>  8);
//    hmsc->bot_data[7] = (uint8_t)(hmsc->scsi_blk_size);
//
//    hmsc->bot_data_length = 8U;
//
//    return 0;
    
    toaster_printf("SCSI_ReadCapacity10\n");
    
    alignas(void*)
    struct [[gnu::packed]] {
        uint32_t blockCount;
        uint32_t blockSize;
    
    } resp = {
        .blockCount = Toastbox::Endian::BFH_U32(Filesystem::_SectorCount-1),
        .blockSize  = Toastbox::Endian::BFH_U32(Filesystem::_BytesPerSector),
    };
    
    Send(0x81, &resp, sizeof(resp));
}

static void SCSI_ModeSense6(uint8_t lun, uint8_t *params) {
    
    toaster_printf("SCSI_ModeSense6\n");
    
    alignas(void*)
    static uint8_t resp[] = {
        0x03,
        0x00,
        0x80, // Read-only==0x80, Read-write==0x00
        0x00,
    };
    const size_t len = std::min((size_t)params[4], sizeof(resp));
    Send(0x81, resp, len);
}

static void SCSI_AllowPreventRemovable(uint8_t lun, uint8_t *params) {
    toaster_printf("SCSI_AllowPreventRemovable\n");
    
//    hmsc->scsi_medium_state = (params[4] ? SCSI_MEDIUM_LOCKED : SCSI_MEDIUM_UNLOCKED);
//    hmsc->bot_data_length = 0U;
}

static void SCSI_Read10(uint8_t lun, uint8_t* params) {
    struct [[gnu::packed]] {
        uint8_t op;
        uint8_t flags;
        uint32_t blockAddr;
        uint8_t groupNumber;
        uint16_t blockLen;
        uint8_t control;
    } cmd;
    
    memcpy(&cmd, params, sizeof(cmd));
    cmd.blockAddr = Toastbox::Endian::HFB_U32(cmd.blockAddr);
    cmd.blockLen = Toastbox::Endian::HFB_U16(cmd.blockLen);
    
//    constexpr size_t ChunkLen = 512;
    const uint8_t* Fs = (const uint8_t*)&Filesystem::_Data;
    const uint8_t* DataStartAddr = (const uint8_t*)&Filesystem::_Data.data;
    
    const uint8_t* addr = Fs+(cmd.blockAddr*Filesystem::_BytesPerSector);
    size_t rem = cmd.blockLen*Filesystem::_BytesPerSector;
    
//    const uint8_t* massData = (const uint8_t*)0x20010000;
    
    toaster_printf("SCSI_Read10 %u %u (0x%x %u)\n",
        (uint32_t)cmd.blockAddr, (uint32_t)cmd.blockLen,
        (uint32_t)addr, (uint32_t)rem
    );
    
//    AssertLED(addr+len <= fs+sizeof(Filesystem::_Data));
    
    if (addr < DataStartAddr) {
        const size_t chunkLen = std::min(rem, (size_t)(DataStartAddr-addr));
        Send(0x81, addr, chunkLen);
        rem -= chunkLen;
        addr += chunkLen;
    }
    
    while (rem) {
        const uint8_t* MassData = (const uint8_t*)0x20010000;
        constexpr size_t ChunkLen = 63*1024;
        
        const size_t chunkLen = std::min(rem, ChunkLen);
        Send(0x81, MassData, chunkLen);
        rem -= chunkLen;
    } 
    
//    while (addr < DataStartAddr) {
//        for (size_t rem=len; rem;) {
//            const size_t chunkLen = std::min(rem, ChunkLen);
//            AssertLED(chunkLen == 512);
//            Send(0x81, addr, chunkLen);
//            rem -= chunkLen;
//            addr += chunkLen;
//        }
//    }
    
    toaster_printf("SCSI_Read10 SENT\n");
    
//    if (!(len % 512)) {
//        Send(0x81, nullptr, 0);
//    }
    
//    AssertLED(len == 512);
//    AssertLED((len % 512) == 0);
//    AssertLED(len == sizeof(Filesystem::_Data));
    
//    static int i = 0;
//    i++;
//    if (i > 1) {
//        AssertLED(false);
//    }
    
//    AssertLED(false);
}

#define SCSI_TEST_UNIT_READY                        0x00U
#define SCSI_INQUIRY                                0x12U
#define SCSI_MODE_SENSE6                            0x1AU
#define SCSI_ALLOW_MEDIUM_REMOVAL                   0x1EU
#define SCSI_READ_CAPACITY10                        0x25U
#define SCSI_READ10                                 0x28U

static void SCSI_ProcessCmd(uint8_t lun, uint8_t *cmd) {
    switch (cmd[0]) {
    case SCSI_TEST_UNIT_READY:        return SCSI_TestUnitReady(lun, cmd);
    case SCSI_INQUIRY:                return SCSI_Inquiry(lun, cmd);
    case SCSI_ALLOW_MEDIUM_REMOVAL:   return SCSI_AllowPreventRemovable(lun, cmd);
    case SCSI_MODE_SENSE6:            return SCSI_ModeSense6(lun, cmd);
    case SCSI_READ_CAPACITY10:        return SCSI_ReadCapacity10(lun, cmd);
    case SCSI_READ10:                 return SCSI_Read10(lun, cmd);
    }
    
    toaster_printf("SCSI_ProcessCmd-UNKNOWN\n");
}

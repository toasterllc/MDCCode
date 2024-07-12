static void SCSI_TestUnitReady(uint8_t lun, uint8_t *params) {
}

static void SCSI_Inquiry(uint8_t lun, uint8_t *params) {
    if ((params[1] & 0x01U) != 0U) /* Evpd is set */
    {
        if (params[2] == 0U) /* Request for Supported Vital Product Data Pages*/
        {
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
            Assert(false);
        }
    }
    else
    {
        static constexpr size_t STANDARD_INQUIRY_DATA_LEN = 0x24;
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
    struct [[gnu::packed]] {
        uint32_t blockCount;
        uint32_t blockSize;
    
    } resp = {
        .blockCount = Filesystem::_SectorCount-1,
        .blockSize  = Filesystem::_BytesPerSector,
    };
    
    Send(0x81, &resp, sizeof(resp));
}

static void SCSI_ModeSense6(uint8_t lun, uint8_t *params) {
    static uint8_t resp[] = {
        0x03,
        0x00,
        0x00, // Read-only==0x80, Read-write==0x00
        0x00,
    };
    const size_t len = std::min((size_t)params[4], sizeof(resp));
    Send(0x81, resp, len);
}

static void SCSI_AllowPreventRemovable(uint8_t lun, uint8_t *params) {
//    hmsc->scsi_medium_state = (params[4] ? SCSI_MEDIUM_LOCKED : SCSI_MEDIUM_UNLOCKED);
//    hmsc->bot_data_length = 0U;
}

static void SCSI_Read10(uint8_t lun, uint8_t* params) {
    const uint32_t blockAddr = ((uint32_t)params[2] << 24) |
                               ((uint32_t)params[3] << 16) |
                               ((uint32_t)params[4] <<  8) |
                               ((uint32_t)params[5] <<  0) ;
    
    const size_t blockLen = ((uint32_t)params[7] << 8) | (uint32_t)params[8];
    constexpr size_t ChunkLen = 512;
    const uint8_t* fs = (const uint8_t*)&Filesystem::_Data;
    const uint8_t* addr = fs+(blockAddr*Filesystem::_BytesPerSector);
    const size_t len = blockLen*Filesystem::_BytesPerSector;
    
    for (size_t rem=len; rem;) {
        const size_t chunkLen = std::min(rem, ChunkLen);
        Send(0x81, addr, chunkLen);
        rem -= chunkLen;
        addr += chunkLen;
    }
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
}

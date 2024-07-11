static int8_t SCSI_UpdateBotData(USBD_MSC_BOT_HandleTypeDef *hmsc,
                                 const uint8_t *pBuff, uint16_t length)
{
  uint16_t len = length;

  hmsc->bot_data_length = len;

  while (len != 0U)
  {
    len--;
    hmsc->bot_data[len] = pBuff[len];
  }

  return 0;
}

static int8_t SCSI_TestUnitReady(USBD_HandleTypeDef *pdev, uint8_t lun, uint8_t *params)
{
  UNUSED(params);
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;

  /* case 9 : Hi > D0 */
  if (hmsc->cbw.dDataLength != 0U)
  {
    SCSI_SenseCode(pdev, hmsc->cbw.bLUN, ILLEGAL_REQUEST, INVALID_CDB);

    return -1;
  }

  if (hmsc->scsi_medium_state == SCSI_MEDIUM_EJECTED)
  {
    SCSI_SenseCode(pdev, lun, NOT_READY, MEDIUM_NOT_PRESENT);
    hmsc->bot_state = USBD_BOT_NO_DATA;
    return -1;
  }

  if (((USBD_StorageTypeDef *)pdev->pUserData)->IsReady(lun) != 0)
  {
    SCSI_SenseCode(pdev, lun, NOT_READY, MEDIUM_NOT_PRESENT);
    hmsc->bot_state = USBD_BOT_NO_DATA;

    return -1;
  }
  hmsc->bot_data_length = 0U;

  return 0;
}

static uint8_t MSC_Page00_Inquiry_Data[] =
{
    0x00,
    0x00,
    0x00,
    0x02,
    0x00,
    0x80,
};

static uint8_t MSC_Page80_Inquiry_Data[] =
{
    0x00,
    0x80,
    0x00,
    0x08,
    0x20,     /* Put Product Serial number */
    0x20,
    0x20,
    0x20,
 };

static int8_t SCSI_Inquiry(USBD_HandleTypeDef *pdev, uint8_t lun, uint8_t *params)
{
  const uint8_t *pPage;
  uint16_t len;
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;

  if (hmsc->cbw.dDataLength == 0U)
  {
    SCSI_SenseCode(pdev, hmsc->cbw.bLUN, ILLEGAL_REQUEST, INVALID_CDB);
    return -1;
  }

  if ((params[1] & 0x01U) != 0U) /* Evpd is set */
  {
    if (params[2] == 0U) /* Request for Supported Vital Product Data Pages*/
    {
      (void)SCSI_UpdateBotData(hmsc, MSC_Page00_Inquiry_Data, sizeof(MSC_Page00_Inquiry_Data));
    }
    else if (params[2] == 0x80U) /* Request for VPD page 0x80 Unit Serial Number */
    {
      (void)SCSI_UpdateBotData(hmsc, MSC_Page80_Inquiry_Data, sizeof(MSC_Page80_Inquiry_Data));
    }
    else /* Request Not supported */
    {
      SCSI_SenseCode(pdev, hmsc->cbw.bLUN, ILLEGAL_REQUEST,
                     INVALID_FIELED_IN_COMMAND);

      return -1;
    }
  }
  else
  {
    pPage = &((USBD_StorageTypeDef *)pdev->pUserData)->pInquiry[lun * STANDARD_INQUIRY_DATA_LEN];
    len = (uint16_t)pPage[4] + 5U;

    if (params[4] <= len)
    {
      len = params[4];
    }

    (void)SCSI_UpdateBotData(hmsc, pPage, len);
  }

  return 0;
}

static int8_t SCSI_ReadCapacity10(USBD_HandleTypeDef *pdev, uint8_t lun, uint8_t *params)
{
  UNUSED(params);
  int8_t ret;
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;

  ret = ((USBD_StorageTypeDef *)pdev->pUserData)->GetCapacity(lun, &hmsc->scsi_blk_nbr, &hmsc->scsi_blk_size);

  if ((ret != 0) || (hmsc->scsi_medium_state == SCSI_MEDIUM_EJECTED))
  {
    SCSI_SenseCode(pdev, lun, NOT_READY, MEDIUM_NOT_PRESENT);
    return -1;
  }

  hmsc->bot_data[0] = (uint8_t)((hmsc->scsi_blk_nbr - 1U) >> 24);
  hmsc->bot_data[1] = (uint8_t)((hmsc->scsi_blk_nbr - 1U) >> 16);
  hmsc->bot_data[2] = (uint8_t)((hmsc->scsi_blk_nbr - 1U) >>  8);
  hmsc->bot_data[3] = (uint8_t)(hmsc->scsi_blk_nbr - 1U);

  hmsc->bot_data[4] = (uint8_t)(hmsc->scsi_blk_size >>  24);
  hmsc->bot_data[5] = (uint8_t)(hmsc->scsi_blk_size >>  16);
  hmsc->bot_data[6] = (uint8_t)(hmsc->scsi_blk_size >>  8);
  hmsc->bot_data[7] = (uint8_t)(hmsc->scsi_blk_size);

  hmsc->bot_data_length = 8U;

  return 0;

}

static uint8_t MSC_Mode_Sense6_data[] =
{
  0x03,
  0x00,
  0x00, // Read-only==0x80, Read-write==0x00
  0x00,
};

static int8_t SCSI_ModeSense6(USBD_HandleTypeDef *pdev, uint8_t lun, uint8_t *params)
{
  UNUSED(lun);
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;
  uint16_t len = sizeof(MSC_Mode_Sense6_data);

  if (params[4] <= len)
  {
    len = params[4];
  }

  (void)SCSI_UpdateBotData(hmsc, MSC_Mode_Sense6_data, len);

  return 0;
}

void SCSI_SenseCode(USBD_HandleTypeDef *pdev, uint8_t lun, uint8_t sKey, uint8_t ASC)
{
  UNUSED(lun);
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;

  hmsc->scsi_sense[hmsc->scsi_sense_tail].Skey = sKey;
  hmsc->scsi_sense[hmsc->scsi_sense_tail].w.b.ASC = ASC;
  hmsc->scsi_sense[hmsc->scsi_sense_tail].w.b.ASCQ = 0U;
  hmsc->scsi_sense_tail++;

  if (hmsc->scsi_sense_tail == SENSE_LIST_DEEPTH)
  {
    hmsc->scsi_sense_tail = 0U;
  }
}

static int8_t SCSI_AllowPreventRemovable(USBD_HandleTypeDef *pdev, uint8_t lun, uint8_t *params)
{
  UNUSED(lun);
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;

  if (params[4] == 0U)
  {
    hmsc->scsi_medium_state = SCSI_MEDIUM_UNLOCKED;
  }
  else
  {
    hmsc->scsi_medium_state = SCSI_MEDIUM_LOCKED;
  }

  hmsc->bot_data_length = 0U;

  return 0;
}

static int8_t SCSI_Read10(USBD_HandleTypeDef *pdev, uint8_t lun, uint8_t *params)
{
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;

  if (hmsc->bot_state == USBD_BOT_IDLE) /* Idle */
  {
    /* case 10 : Ho <> Di */
    if ((hmsc->cbw.bmFlags & 0x80U) != 0x80U)
    {
      SCSI_SenseCode(pdev, hmsc->cbw.bLUN, ILLEGAL_REQUEST, INVALID_CDB);
      return -1;
    }

    if (hmsc->scsi_medium_state == SCSI_MEDIUM_EJECTED)
    {
      SCSI_SenseCode(pdev, lun, NOT_READY, MEDIUM_NOT_PRESENT);

      return -1;
    }

    if (((USBD_StorageTypeDef *)pdev->pUserData)->IsReady(lun) != 0)
    {
      SCSI_SenseCode(pdev, lun, NOT_READY, MEDIUM_NOT_PRESENT);
      return -1;
    }

    hmsc->scsi_blk_addr = ((uint32_t)params[2] << 24) |
                          ((uint32_t)params[3] << 16) |
                          ((uint32_t)params[4] <<  8) |
                          (uint32_t)params[5];

    hmsc->scsi_blk_len = ((uint32_t)params[7] <<  8) | (uint32_t)params[8];

    if (SCSI_CheckAddressRange(pdev, lun, hmsc->scsi_blk_addr,
                               hmsc->scsi_blk_len) < 0)
    {
      return -1; /* error */
    }

    /* cases 4,5 : Hi <> Dn */
    if (hmsc->cbw.dDataLength != (hmsc->scsi_blk_len * hmsc->scsi_blk_size))
    {
      SCSI_SenseCode(pdev, hmsc->cbw.bLUN, ILLEGAL_REQUEST, INVALID_CDB);
      return -1;
    }

    hmsc->bot_state = USBD_BOT_DATA_IN;
  }
  hmsc->bot_data_length = MSC_MEDIA_PACKET;

  return SCSI_ProcessRead(pdev, lun);
}

static int8_t SCSI_CheckAddressRange(USBD_HandleTypeDef *pdev, uint8_t lun,
                                     uint32_t blk_offset, uint32_t blk_nbr)
{
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;

  if ((blk_offset + blk_nbr) > hmsc->scsi_blk_nbr)
  {
    SCSI_SenseCode(pdev, lun, ILLEGAL_REQUEST, ADDRESS_OUT_OF_RANGE);
    return -1;
  }

  return 0;
}

static int8_t SCSI_ProcessRead(USBD_HandleTypeDef *pdev, uint8_t lun)
{
  USBD_MSC_BOT_HandleTypeDef *hmsc = (USBD_MSC_BOT_HandleTypeDef *)pdev->pClassData;
  uint32_t len = hmsc->scsi_blk_len * hmsc->scsi_blk_size;

  len = MIN(len, MSC_MEDIA_PACKET);

  if (((USBD_StorageTypeDef *)pdev->pUserData)->Read(lun, hmsc->bot_data,
                                                     hmsc->scsi_blk_addr,
                                                     (len / hmsc->scsi_blk_size)) < 0)
  {
    SCSI_SenseCode(pdev, lun, HARDWARE_ERROR, UNRECOVERED_READ_ERROR);
    return -1;
  }

  (void)USBD_LL_Transmit(pdev, MSC_EPIN_ADDR, hmsc->bot_data, len);

  hmsc->scsi_blk_addr += (len / hmsc->scsi_blk_size);
  hmsc->scsi_blk_len -= (len / hmsc->scsi_blk_size);

  /* case 6 : Hi = Di */
  hmsc->csw.dDataResidue -= len;

  if (hmsc->scsi_blk_len == 0U)
  {
    hmsc->bot_state = USBD_BOT_LAST_DATA_IN;
  }

  return 0;
}


int8_t SCSI_ProcessCmd(USBD_HandleTypeDef *pdev, uint8_t lun, uint8_t *cmd) {
    switch (cmd[0]) {
    case SCSI_TEST_UNIT_READY:        return SCSI_TestUnitReady(pdev, lun, cmd);
    case SCSI_INQUIRY:                return SCSI_Inquiry(pdev, lun, cmd);
    case SCSI_ALLOW_MEDIUM_REMOVAL:   return SCSI_AllowPreventRemovable(pdev, lun, cmd);
    case SCSI_MODE_SENSE6:            return SCSI_ModeSense6(pdev, lun, cmd);
    case SCSI_READ_CAPACITY10:        return SCSI_ReadCapacity10(pdev, lun, cmd);
    case SCSI_READ10:                 return SCSI_Read10(pdev, lun, cmd);
    }
}

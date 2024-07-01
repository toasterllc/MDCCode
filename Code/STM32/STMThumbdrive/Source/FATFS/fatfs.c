/**
  ******************************************************************************
  * @file   fatfs.c
  * @brief  Code for fatfs applications
  ******************************************************************************
  * @attention
  *
  * <h2><center>&copy; Copyright (c) 2024 STMicroelectronics.
  * All rights reserved.</center></h2>
  *
  * This software component is licensed by ST under Ultimate Liberty license
  * SLA0044, the "License"; You may not use this file except in compliance with
  * the License. You may obtain a copy of the License at:
  *                             www.st.com/SLA0044
  *
  ******************************************************************************
  */

#include "fatfs.h"
#include <string.h>
#include "storage.h"

/* USER CODE BEGIN Variables */

/* USER CODE END Variables */

void MX_FATFS_Init(void)
{
    /*## FatFS: Link the USER driver ###########################*/
    FATFS_LinkDriver(&USER_Driver, "");
    
    // Create filesystem
    FRESULT fr = 0;
    uint8_t work[1024];
//    uint8_t work[32*1024];
    fr = f_mkfs("", FM_FAT, STORAGE_SECTOR_SIZE, work, sizeof(work));
    assert(fr == FR_OK);
    
    // Mount filesystem
    FATFS FatFS = {};
    fr = f_mount(&FatFS, "", 1);
    assert(fr == FR_OK);
    
    
    
    
    
    
//	FR_OK = 0,				/* (0) Succeeded */
//	FR_DISK_ERR,			/* (1) A hard error occurred in the low level disk I/O layer */
//	FR_INT_ERR,				/* (2) Assertion failed */
//	FR_NOT_READY,			/* (3) The physical drive cannot work */
//	FR_NO_FILE,				/* (4) Could not find the file */
//	FR_NO_PATH,				/* (5) Could not find the path */
//	FR_INVALID_NAME,		/* (6) The path name format is invalid */
//	FR_DENIED,				/* (7) Access denied due to prohibited access or directory full */
//	FR_EXIST,				/* (8) Access denied due to prohibited access */
//	FR_INVALID_OBJECT,		/* (9) The file/directory object is invalid */
//	FR_WRITE_PROTECTED,		/* (10) The physical drive is write protected */
//	FR_INVALID_DRIVE,		/* (11) The logical drive number is invalid */
//	FR_NOT_ENABLED,			/* (12) The volume has no work area */
//	FR_NO_FILESYSTEM,		/* (13) There is no valid FAT volume */
//	FR_MKFS_ABORTED,		/* (14) The f_mkfs() aborted due to any problem */
//	FR_TIMEOUT,				/* (15) Could not get a grant to access the volume within defined period */
//	FR_LOCKED,				/* (16) The operation is rejected according to the file sharing policy */
//	FR_NOT_ENOUGH_CORE,		/* (17) LFN working buffer could not be allocated */
//	FR_TOO_MANY_OPEN_FILES,	/* (18) Number of open files > _FS_LOCK */
//	FR_INVALID_PARAMETER	/* (19) Given parameter is invalid */
    
    
    
    
    
//	FR_WRITE_PROTECTED,		/* (10) The physical drive is write protected */
//	FR_INVALID_DRIVE,		/* (11) The logical drive number is invalid */
//	FR_NOT_ENABLED,			/* (12) The volume has no work area */
//	FR_NO_FILESYSTEM,		/* (13) There is no valid FAT volume */
//	FR_MKFS_ABORTED,		/* (14) The f_mkfs() aborted due to any problem */

//	FR_TIMEOUT,				/* (15) Could not get a grant to access the volume within defined period */
//	FR_LOCKED,				/* (16) The operation is rejected according to the file sharing policy */
//	FR_NOT_ENOUGH_CORE,		/* (17) LFN working buffer could not be allocated */
//	FR_TOO_MANY_OPEN_FILES,	/* (18) Number of open files > _FS_LOCK */
//	FR_INVALID_PARAMETER	/* (19) Given parameter is invalid */

    
    
    // Write file
    FIL f;
    fr = f_open(&f, "test.txt", FA_WRITE | FA_CREATE_ALWAYS);
    assert(fr == FR_OK);
    
    UINT x;
    const char text[] = "hello";
    fr = f_write(&f, text, strlen(text), &x);
    assert(fr == FR_OK);
    
    fr = f_close(&f);
    assert(fr == FR_OK);
    
    // Unmount
    fr = f_mount(&FatFS, "", 0);
    assert(fr == FR_OK);
  
  

  /* USER CODE BEGIN Init */
  /* additional user code for init */
  /* USER CODE END Init */
}

/**
  * @brief  Gets Time from RTC
  * @param  None
  * @retval Time in DWORD
  */
DWORD get_fattime(void)
{
  /* USER CODE BEGIN get_fattime */
  return 0;
  /* USER CODE END get_fattime */
}

/* USER CODE BEGIN Application */

/* USER CODE END Application */

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/

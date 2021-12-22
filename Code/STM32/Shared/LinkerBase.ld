ENTRY(ISR_Reset)

_sitcm_ram      = ORIGIN(ITCM_RAM);
_eitcm_ram      = ORIGIN(ITCM_RAM) + LENGTH(ITCM_RAM);
_sitcm_flash    = ORIGIN(ITCM_FLASH);
_eitcm_flash    = ORIGIN(ITCM_FLASH) + LENGTH(ITCM_FLASH);
_saxim_flash    = ORIGIN(AXIM_FLASH);
_eaxim_flash    = ORIGIN(AXIM_FLASH) + LENGTH(AXIM_FLASH);
_sdtcm_ram      = ORIGIN(DTCM_RAM);
_edtcm_ram      = ORIGIN(DTCM_RAM) + LENGTH(DTCM_RAM);
_ssram1         = ORIGIN(SRAM1);
_esram1         = ORIGIN(SRAM1) + LENGTH(SRAM1);
_ssram2         = ORIGIN(SRAM2);
_esram2         = ORIGIN(SRAM2) + LENGTH(SRAM2);

MEMORY {
    ITCM_RAM(rwx):  ORIGIN = 0x00000000, LENGTH = 16K
    ITCM_FLASH(rx): ORIGIN = 0x00200000, LENGTH = 64K
    AXIM_FLASH(rx): ORIGIN = 0x08000000, LENGTH = 64K
    DTCM_RAM(rwx):  ORIGIN = 0x20000000, LENGTH = 64K
    SRAM1(rw):      ORIGIN = 0x20010000, LENGTH = 176K
    SRAM2(rw):      ORIGIN = 0x2003C000, LENGTH = 16K
    /* The bootloader uses SRAM2 as its RAM, so don't store application sections that
       are written by the bootloader in SRAM2, otherwise the bootloader will clobber
       its own RAM while copying the application into place. */
}

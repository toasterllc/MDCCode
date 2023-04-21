MEMORY {
    BAKMEM : ORIGIN = 0x0660, LENGTH = 0x0020
}

SECTIONS {
    /* Info FRAM */
    .fram_info : {
        . = ALIGN(2);
        *(.fram_info.*)
        . = ALIGN(2);
    } >INFOMEM
    
    /* Backup RAM (RAM maintained during LPM3.5) */
    .ram_backup_bss : {
        _ram_backup_bss_start = .;
        *(.ram_backup_bss.*)
        _ram_backup_bss_end = .;
    } >BAKMEM
    
    /* Backup RAM (RAM maintained during LPM3.5), uninitialized */
    .ram_backup_noinit (NOLOAD) : {
        *(.ram_backup_noinit.*)
    } >BAKMEM
}

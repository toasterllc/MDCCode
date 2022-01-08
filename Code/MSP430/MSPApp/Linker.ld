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
    .ram_backup : {
        . = ALIGN(2);
        _ram_backup_src = LOADADDR(.ram_backup);
        _ram_backup_dststart = .;
        *(.ram_backup.*)
        . = ALIGN(2);
        _ram_backup_dstend = .;
    } >BAKMEM AT> FRAM
    
    /* Backup RAM (RAM maintained during LPM3.5) */
    .ram_backup_noinit : {
        . = ALIGN(2);
        *(.ram_backup_noinit.*)
    } >BAKMEM AT> FRAM
}

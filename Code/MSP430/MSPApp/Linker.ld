MEMORY {
    BAKMEM : ORIGIN = 0x0660, LENGTH = 0x0020
}

SECTIONS {
    /* Info FRAM */
    .infomem : {
        . = ALIGN(2);
        *(.infomem)
        . = ALIGN(2);
    } >INFOMEM
    
    /* Backup memory (RAM maintained during LPM3.5) */
    .bakmem : {
        . = ALIGN(2);
        _sbakmem_fram = LOADADDR(.bakmem);
        _sbakmem_ram = .;
        *(.bakmem)
        . = ALIGN(2);
        _ebakmem_ram = .;
    } >BAKMEM AT> FRAM
}

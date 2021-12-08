MEMORY {
    BAKMEM : ORIGIN = 0x0660, LENGTH = 0x0020
}

SECTIONS {
    /* Backup memory (RAM maintained during LPM3.5) */
    .bakmem : {
        . = ALIGN(2);
        _sbakmem_fram = LOADADDR(.bakmem);
        _sbakmem_ram = .;
        *(.bakmem)
        *(.bakmem*)
        . = ALIGN(2);
        _ebakmem_ram = .;
    } >BAKMEM AT> FRAM
}

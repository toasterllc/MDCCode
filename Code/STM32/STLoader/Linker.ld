StackSize = 0x400;
ENTRY(ISR_Reset)

MEMORY {
    FLASH     (rx)    : ORIGIN = 0x8000000,   LENGTH = 64K
    APP_RAM   (r)     : ORIGIN = 0x20000000,  LENGTH = 248K   /* RAM reserved for application */
    RAM       (rwx)   : ORIGIN = 0x2003E000,  LENGTH = 8K     /* RAM reserved for bootloader */
}

SECTIONS {

    .isr_vector : {
        . = ALIGN(4);
        _sisr_vector = .;
        KEEP(*(.isr_vector))
        . = ALIGN(4);
    } >FLASH
    
    .text : {
        . = ALIGN(4);
        *(.text)
        *(.text*)
        *(.glue_7) /* glue arm to thumb code */
        *(.glue_7t) /* glue thumb to arm code */
        *(.eh_frame)
        KEEP(*(.init))
        KEEP(*(.fini))
        . = ALIGN(4);
    } >FLASH
    
    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } >FLASH
    
    .ARM.extab : {
        . = ALIGN(4);
        *(.ARM.extab*)
        *(.gnu.linkonce.armextab.*)
        . = ALIGN(4);
    } >FLASH
    
    .ARM : {
        . = ALIGN(4);
        *(.ARM.exidx*)
        . = ALIGN(4);
    } >FLASH
    
    .preinit_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array*))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } >FLASH
    
    .init_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array*))
        PROVIDE_HIDDEN(__init_array_end = .);
    } >FLASH
    
    .fini_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array*))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } >FLASH
    
    .data : {
        . = ALIGN(4);
        _sdata_flash = LOADADDR(.data);
        _sdata_ram = .;
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata_ram = .;
    } >RAM AT> FLASH
    
    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >RAM
    
    .noinit : {
        . = ALIGN(4);
        *(.noinit)
        *(.noinit*)
        . = ALIGN(4);
    } >RAM
    
    .stack : {
        . = ALIGN(4);
        _sstack = .;
        . = . + StackSize;
        . = ALIGN(4);
        _estack = .;
    } >RAM
    
    .app_ram : {
        _sapp_ram = .;
        . = . + LENGTH(APP_RAM);
        _eapp_ram = .;
    } >APP_RAM
    
    /* Remove information from the compiler libraries */
    /DISCARD/ : {
        libc.a(*)
        libm.a(*)
        libgcc.a(*)
    }
    
    .ARM.attributes 0 : {
        *(.ARM.attributes)
    }
}

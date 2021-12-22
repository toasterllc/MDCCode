INCLUDE LinkerBase.ld

SECTIONS {

    .isr : {
        . = ALIGN(4);
        _sisr = .;
        /* VectorTable needs to be at the beginning of .isr to ensure it's at 0x200000 */
        KEEP(*(.isr.VectorTable))
        KEEP(*(.isr))
        . = ALIGN(4);
    } >ITCM_FLASH
    
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
    } >ITCM_FLASH
    
    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } >ITCM_FLASH
    
    .ARM.extab : {
        . = ALIGN(4);
        *(.ARM.extab*)
        *(.gnu.linkonce.armextab.*)
        . = ALIGN(4);
    } >ITCM_FLASH
    
    .ARM : {
        . = ALIGN(4);
        *(.ARM.exidx*)
        . = ALIGN(4);
    } >ITCM_FLASH
    
    .preinit_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array*))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } >ITCM_FLASH
    
    .init_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array*))
        PROVIDE_HIDDEN(__init_array_end = .);
    } >ITCM_FLASH
    
    .fini_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array*))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } >ITCM_FLASH
    
    .data : {
        . = ALIGN(4);
        _sdata_flash = LOADADDR(.data);
        _sdata_ram = .;
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata_ram = .;
    } >SRAM2 AT> ITCM_FLASH
    
    .bss : {
        . = ALIGN(4);
        _sbss = .;
        __bss_start__ = .;
        *(.bss)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
        __bss_end__ = .;
    } >SRAM2
    
    .uninit (NOLOAD) : {
        . = ALIGN(4);
        *(.uninit)
        *(.uninit*)
        . = ALIGN(4);
    } >SRAM2
    
    .stack (NOLOAD) : {
        . = ALIGN(4);
        *(.stack)
        *(.stack.*)
        . = ALIGN(4);
    } >SRAM2
    
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

INCLUDE LinkerBase.ld

SECTIONS {

    .isr : {
        . = ALIGN(4);
        _sisr = .;
        /* VectorTable needs to be at the beginning of .isr to ensure it's at 0x200000 */
        KEEP(*(.isr.VectorTable))
        KEEP(*(.isr))
        . = ALIGN(4);
    } >ITCM_RAM
    
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
    } >DTCM_RAM
    
    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } >DTCM_RAM
    
    .ARM.extab : {
        . = ALIGN(4);
        *(.ARM.extab*)
        *(.gnu.linkonce.armextab.*)
        . = ALIGN(4);
    } >DTCM_RAM
    
    .ARM : {
        . = ALIGN(4);
        *(.ARM.exidx*)
        . = ALIGN(4);
    } >DTCM_RAM
    
    .preinit_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array*))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } >DTCM_RAM
    
    .init_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array*))
        PROVIDE_HIDDEN(__init_array_end = .);
    } >DTCM_RAM
    
    .fini_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array*))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } >DTCM_RAM
    
    .data : {
        . = ALIGN(4);
        _sdata_flash = LOADADDR(.data);
        _sdata_ram = .;
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata_ram = .;
    } >DTCM_RAM
    
    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >DTCM_RAM
    
    .uninit (NOLOAD) : {
        . = ALIGN(4);
        *(.uninit)
        *(.uninit*)
        . = ALIGN(4);
    } >DTCM_RAM
    
    .stack (NOLOAD) : {
        . = ALIGN(4);
        *(.stack)
        *(.stack.*)
        . = ALIGN(4);
    } >DTCM_RAM
    
    .sram1 : {
        . = ALIGN(4);
        *(.sram1)
        *(.sram1*)
        . = ALIGN(4);
    } >SRAM1
    
    /* SRAM2 is marked NOLOAD to prevent it from being initialized,
       because it's used by the bootloader. See details under the
       MEMORY portion of this file. */
    .sram2 (NOLOAD) : {
        . = ALIGN(4);
        *(.sram2)
        *(.sram2*)
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

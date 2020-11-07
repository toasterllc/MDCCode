StackSize = 0x400;
ENTRY(ISR_Reset)

MEMORY {
    /* Stay out of the last 8K, which is reserved for the bootloader. */
    RAM(rwx): ORIGIN = 0x20000000, LENGTH = 248K
}

SECTIONS {

    .isr_vector : {
        . = ALIGN(4);
        _sisr_vector = .;
        KEEP(*(.isr_vector))
        . = ALIGN(4);
    } >RAM
    
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
    } >RAM
    
    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } >RAM
    
    .ARM.extab : {
        . = ALIGN(4);
        *(.ARM.extab*)
        *(.gnu.linkonce.armextab.*)
        . = ALIGN(4);
    } >RAM
    
    .ARM : {
        . = ALIGN(4);
        *(.ARM.exidx*)
        . = ALIGN(4);
    } >RAM
    
    .preinit_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array*))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } >RAM
    
    .init_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array*))
        PROVIDE_HIDDEN(__init_array_end = .);
    } >RAM
    
    .fini_array : {
        . = ALIGN(4);
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array*))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } >RAM
    
    .data : {
        . = ALIGN(4);
        _sdata_flash = LOADADDR(.data);
        _sdata_ram = .;
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata_ram = .;
    } >RAM
    
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

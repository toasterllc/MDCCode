MEMORY {
    BAKMEM : ORIGIN = 0x0660, LENGTH = 0x0020
}

SECTIONS {
    .bakmem : {} > BAKMEM     /* Backup memory */
}

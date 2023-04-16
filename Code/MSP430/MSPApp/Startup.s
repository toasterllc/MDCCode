.global _ResetVector
.extern _Startup

/* Reset Vector */
.section .resetvec
.type _ResetVector, %object
_ResetVector:
    .word _Startup

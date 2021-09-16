#pragma once
#include <stdbool.h>
#include <stdlib.h>

#define MEOWBUFLEN ((176*1024))
#define MEOWSENDLEN (1<<19)-512

#define USB_OTG_DIEPMSK_NAKM_Pos                 (13U)
#define USB_OTG_DIEPMSK_NAKM_Msk                 (0x1UL << USB_OTG_DIEPMSK_NAKM_Pos) /*!< 0x00002000 */
#define USB_OTG_DIEPMSK_NAKM                     USB_OTG_DIEPMSK_NAKM_Msk       /*!< NAK interrupt mask                                */

inline void Assert(bool x) {
    if (!x) abort();
}

//#define AssertArg(x)
inline void AssertArg(bool x) {
    if (!x) abort();
}

/******************************************************************************
 *                          Reusable MSP430 mspprintf()
 *
 * Description: This mspprintf function was written by oPossum and originally
 *              posted on the 43oh.com forums. For more information on this
 *              code, please see the link below.
 *
 *              http://www.43oh.com/forum/viewtopic.php?f=10&t=1732
 *
 *              A big thanks to oPossum for sharing such great code!
 *
 * Author:  oPossum
 * Source:  http://www.43oh.com/forum/viewtopic.php?f=10&t=1732
 * Date:    10-17-11
 *
 * Note: This comment section was written by Nicholas J. Conn on 06-07-2012
 *       for use on NJC's MSP430 LaunchPad Blog.
 ******************************************************************************/

#include <stdarg.h>
#include <stdint.h>

extern "C" int putchar(int c);

static const unsigned long dv[] = {
//  4294967296      // 32 bit unsigned max
        1000000000,// +0
        100000000, // +1
        10000000, // +2
        1000000, // +3
        100000, // +4
//       65535      // 16 bit unsigned max
        10000, // +5
        1000, // +6
        100, // +7
        10, // +8
        1, // +9
        };

static void xtoa(unsigned long x, const unsigned long *dp) {
    char c;
    unsigned long d;
    if (x) {
        while (x < *dp)
            ++dp;
        do {
            d = *dp++;
            c = '0';
            while (x >= d)
                ++c, x -= d;
            putchar(c);
        } while (!(d & 1));
    } else
        putchar('0');
}

static void puth(unsigned n) {
    static const char hex[16] = { '0', '1', '2', '3', '4', '5', '6', '7', '8',
            '9', 'A', 'B', 'C', 'D', 'E', 'F' };
    putchar(hex[n & 15]);
}

int mspprintf(const char* fmt, ...) {
    int8_t c = 0;
    int16_t i = 0;
    int32_t n = 0;
    
    va_list a;
    va_start(a, fmt);
    while ((c = *fmt++)) {
        if (c == '%') {
            switch (c = *fmt++) {
                case 's': // string
                    for (const char* s=va_arg(a, const char*); *s; s++) putchar(*s);
                    break;
                case 'c': // char
                    putchar(va_arg(a, int));
                    break;
                case 'd': // i16
                case 'u': // u16
                    i = va_arg(a, int);
                    if (c == 'd' && i < 0) i = -i, putchar('-');
                    xtoa((uint16_t)i, dv + 5);
                    break;
                case 'l': // i32
                case 'n': // u32
                    n = va_arg(a, int32_t);
                    if (c == 'l' && n < 0) n = -n, putchar('-');
                    xtoa((uint32_t)n, dv);
                    break;
                case 'x': // u16, hex
                    i = va_arg(a, int);
                    puth(i >> 12);
                    puth(i >> 8);
                    puth(i >> 4);
                    puth(i);
                    break;
                case 'X': // u32, hex
                    n = va_arg(a, uint32_t);
                    puth(n >> 28);
                    puth(n >> 24);
                    puth(n >> 20);
                    puth(n >> 16);
                    puth(n >> 12);
                    puth(n >> 8);
                    puth(n >> 4);
                    puth(n);
                    break;
                case 0:
                    return 0;
                default:
                    goto bad_fmt;
            }
        } else
            bad_fmt: putchar(c);
    }
    va_end(a);
    return 0;
}

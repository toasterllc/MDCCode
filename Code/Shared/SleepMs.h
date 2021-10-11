#pragma once

#ifdef __msp430
#warning TODO: implement for real
#define SleepMs(ms) __delay_cycles((((uint64_t)ms)*16000000) / 1000)
#else
void SleepMs(uint32_t ms);
#endif

#!/bin/bash

# Get path to MDCDebugger
dir="$(cd "$(dirname "$0")"; pwd)"
MDCDebugger="$dir/MDCDebugger/MDCDebugger"

# Configure internal register initialization
"$MDCDebugger" pixreg16 0x3052=0xA114

# Start internal register initialization
"$MDCDebugger" pixreg16 0x304A=0x0070

# Wait 150k EXTCLK periods
# (150e3/12e6) = 0.0125 = 13ms
sleep .2

# Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
# (Default value of 0x301A is 0x0058)
"$MDCDebugger" pixreg16 0x301A=0x10D8

# Set pre_pll_clk_div=2
# pre_pll_clk_div=2     ->  CLK_OP=98 MHz
# pre_pll_clk_div=4     ->  CLK_OP=49 MHz
# "$MDCDebugger" pixreg16 0x302E=0x0002     # /2
# "$MDCDebugger" pixreg16 0x302E=0x0004     # /4 (Default)
# "$MDCDebugger" pixreg16 0x302E=0x003F     # /63

# Set pll_multiplier
# "$MDCDebugger" pixreg16 0x3030=0x0062     # *98 (Default)
# "$MDCDebugger" pixreg16 0x3030=0x0031     # *49

# Set vt_pix_clk_div
# "$MDCDebugger" pixreg16 0x302A=0x0006     # /6 (Default)
# "$MDCDebugger" pixreg16 0x302A=0x001F     # /31

# Set output slew rate
# Slow              = 0x0010
# Medium (default)  = 0x9010
# Fast              = 0xFC10
# "$MDCDebugger" pixreg16 0x306E=0x9010
# "$MDCDebugger" pixreg16 0x306E=0x4810
# "$MDCDebugger" pixreg16 0x306E=0xFC10



# # Set test_data_red
# "$MDCDebugger" pixreg16 0x3072=0x0B2A   # AAA
#
# # Set test_data_greenr
# "$MDCDebugger" pixreg16 0x3074=0x0C3B   # BBB
#
# # Set test_data_blue
# "$MDCDebugger" pixreg16 0x3076=0x0D4C   # CCC
#
# # Set test_data_greenb
# "$MDCDebugger" pixreg16 0x3078=0x0C3B   # BBB


# # Set test_data_red
# "$MDCDebugger" pixreg16 0x3072=0x0FFF   # FFF
#
# # Set test_data_greenr
# "$MDCDebugger" pixreg16 0x3074=0x0FFF   # FFF
#
# # Set test_data_blue
# "$MDCDebugger" pixreg16 0x3076=0x0FFF   # FFF
#
# # Set test_data_greenb
# "$MDCDebugger" pixreg16 0x3078=0x0FFF   # FFF




# # Set op_pix_clk_div
# "$MDCDebugger" pixreg16 0x3036=0x000A

# Set test_pattern_mode
# 0: Normal operation (generate output data from pixel array)
# 1: Solid color test pattern.
# 2: Full color bar test pattern
# 3: Fade-to-gray color bar test pattern
# 256: Walking 1s test pattern (12 bit)
"$MDCDebugger" pixreg16 0x3070=0x0000       # Normal operation
# "$MDCDebugger" pixreg16 0x3070=0x0001       # Solid color
# "$MDCDebugger" pixreg16 0x3070=0x0002       # Color bars
# "$MDCDebugger" pixreg16 0x3070=0x0003       # Fade-to-gray
# "$MDCDebugger" pixreg16 0x3070=0x0100       # Walking 1s

# Set data_pedestal
# "$MDCDebugger" pixreg16 0x301E=0x00A8           # Default
# "$MDCDebugger" pixreg16 0x301E=0x0000

# Set serial_format
# *** This register write is necessary for parallel mode.
# *** The datasheet doesn't mention this. :(
# *** Discovered looking at Linux kernel source.
"$MDCDebugger" pixreg16 0x31AE=0x0301

# Set data_format_bits
# Datasheet:
#   "The serial format should be configured using R0x31AC.
#   This register should be programmed to 0x0C0C when
#   using the parallel interface."
"$MDCDebugger" pixreg16 0x31AC=0x0C0C

# Set row_speed
# 0 cycle delay             = 0x0000
# 1/2 cycle delay (default) = 0x0010
# "$MDCDebugger" pixreg16 0x3028=0x0000       # 0 cycle delay
# "$MDCDebugger" pixreg16 0x3028=0x0010       # 1/2 cycle delay (default)

# # Set the x-start address
# # Default = 0x0006
# # "$MDCDebugger" pixreg16 0x3004=0x0006       # Default
# "$MDCDebugger" pixreg16 0x3004=0x0010
#
# Set the x-end address
# Default = 0x0905
# "$MDCDebugger" pixreg16 0x3008=0x0905       # Default
# "$MDCDebugger" pixreg16 0x3008=0x01B1
#
# # Set the y-start address
# # Default = 0x007C
# # "$MDCDebugger" pixreg16 0x3002=0x007C       # Default
# "$MDCDebugger" pixreg16 0x3002=0x007C
#
# Set the y-end address
# Default = 0x058b
# "$MDCDebugger" pixreg16 0x3006=0x058b       # Default
# "$MDCDebugger" pixreg16 0x3006=0x016B

# Implement "Recommended Default Register Changes and Sequencer"
"$MDCDebugger" pixreg16 0x3ED2=0x0146
"$MDCDebugger" pixreg16 0x3EDA=0x88BC
"$MDCDebugger" pixreg16 0x3EDC=0xAA63
"$MDCDebugger" pixreg16 0x305E=0x00A0

# Disable embedded_data (first 2 rows of statistic info)
# See AR0134_RR_D.pdf for info on statistics format
# Stats enabled (default)   = 0x1902
# Stats disabled            = 0x1802
"$MDCDebugger" pixreg16 0x3064=0x1802

# Start streaming
# (Previous value of 0x301A is 0x10D8, as set above)
"$MDCDebugger" pixreg16 0x301A=0x10DC

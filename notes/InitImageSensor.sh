#!/bin/bash

# Configure internal register initialization
sudo ./MDCDebugger pixreg16 0x3052=0xA114

# Start internal register initialization
sudo ./MDCDebugger pixreg16 0x304A=0x0070

# Wait 150k EXTCLK periods
# (150e3/12e6) = 0.0125 = 13ms
sleep .2

# Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
# (Default value of 0x301A is 0x0058)
sudo ./MDCDebugger pixreg16 0x301A=0x10D8

# Set pre_pll_clk_div=2
# pre_pll_clk_div=2     ->  CLK_OP=98 MHz
# pre_pll_clk_div=4     ->  CLK_OP=49 MHz
sudo ./MDCDebugger pixreg16 0x302E=0x0004
# sudo ./MDCDebugger pixreg16 0x302E=0x0002

# Set output slew rate
# Slow              = 0x0010
# Medium (default)  = 0x9010
# Fast              = 0xFC10
# sudo ./MDCDebugger pixreg16 0x306E=0x9010
# sudo ./MDCDebugger pixreg16 0x306E=0x4810
# sudo ./MDCDebugger pixreg16 0x306E=0xFC10

# # Set test_data_red
# sudo ./MDCDebugger pixreg16 0x3072=0x0B2A   # AAA
#
# # Set test_data_greenr
# sudo ./MDCDebugger pixreg16 0x3074=0x0C3B   # BBB
#
# # Set test_data_blue
# sudo ./MDCDebugger pixreg16 0x3076=0x0D4C   # CCC
#
# # Set test_data_greenb
# sudo ./MDCDebugger pixreg16 0x3078=0x0E5D   # DDD




# Set test_data_red
sudo ./MDCDebugger pixreg16 0x3072=0x0FFF   # FFF

# Set test_data_greenr
sudo ./MDCDebugger pixreg16 0x3074=0x0FFF   # FFF

# Set test_data_blue
sudo ./MDCDebugger pixreg16 0x3076=0x0FFF   # FFF

# Set test_data_greenb
sudo ./MDCDebugger pixreg16 0x3078=0x0FFF   # FFF




# # Set op_pix_clk_div
# sudo ./MDCDebugger pixreg16 0x3036=0x000A

# Set test_pattern_mode
# 0: Normal operation (generate output data from pixel array)
# 1: Solid color test pattern.
# 2: Full color bar test pattern
# 3: Fade-to-gray color bar test pattern
# 256: Walking 1s test pattern (12 bit)
# sudo ./MDCDebugger pixreg16 0x3070=0x0000       # Normal operation
sudo ./MDCDebugger pixreg16 0x3070=0x0001       # Solid color
# sudo ./MDCDebugger pixreg16 0x3070=0x0002       # Color bars
# sudo ./MDCDebugger pixreg16 0x3070=0x0003       # Fade-to-gray
# sudo ./MDCDebugger pixreg16 0x3070=0x0100       # Walking 1s

# Set data_pedestal
# sudo ./MDCDebugger pixreg16 0x301E=0x00A8           # Default
# sudo ./MDCDebugger pixreg16 0x301E=0x0000

# Set serial_format
# *** This register write is necessary for parallel mode.
# *** The datasheet doesn't mention this. :(
# *** Discovered looking at Linux kernel source.
sudo ./MDCDebugger pixreg16 0x31AE=0x0301

# Set data_format_bits
# Datasheet:
#   "The serial format should be configured using R0x31AC.
#   This register should be programmed to 0x0C0C when
#   using the parallel interface."
sudo ./MDCDebugger pixreg16 0x31AC=0x0C0C

# Set row_speed
# 0 cycle delay             = 0x0000
# 1/2 cycle delay (default) = 0x0010
# sudo ./MDCDebugger pixreg16 0x3028=0x0000       # 0 cycle delay
# sudo ./MDCDebugger pixreg16 0x3028=0x0010       # 1/2 cycle delay (default)

# # Set the x-start address
# # Default = 0x0006
# # sudo ./MDCDebugger pixreg16 0x3004=0x0006       # Default
# sudo ./MDCDebugger pixreg16 0x3004=0x0010
#
# # Set the x-end address
# # Default = 0x0905
# # sudo ./MDCDebugger pixreg16 0x3008=0x0905       # Default
# sudo ./MDCDebugger pixreg16 0x3008=0x0060
#
# # Set the y-start address
# # Default = 0x007C
# # sudo ./MDCDebugger pixreg16 0x3002=0x007C       # Default
# sudo ./MDCDebugger pixreg16 0x3002=0x007C
#
# # Set the y-end address
# # Default = 0x058b
# # sudo ./MDCDebugger pixreg16 0x3006=0x058b       # Default
# sudo ./MDCDebugger pixreg16 0x3006=0x00CC

# Implement "Recommended Default Register Changes and Sequencer"
sudo ./MDCDebugger pixreg16 0x3ED2=0x0146
sudo ./MDCDebugger pixreg16 0x3EDA=0x88BC
sudo ./MDCDebugger pixreg16 0x3EDC=0xAA63
sudo ./MDCDebugger pixreg16 0x305E=0x00A0

# Disable embedded_data (first 2 rows of statistic info)
# See AR0134_RR_D.pdf for info on statistics format
# Stats enabled (default)   = 0x1902
# Stats disabled            = 0x1802
sudo ./MDCDebugger pixreg16 0x3064=0x1802

# Start streaming
# (Previous value of 0x301A is 0x10D8, as set above)
sudo ./MDCDebugger pixreg16 0x301A=0x10DC

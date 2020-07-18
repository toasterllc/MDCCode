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

# Set output slew rate
# Slow              = 0x0010
# Medium (default)  = 0x9010
# Fast              = 0xFC10
sudo ./MDCDebugger pixreg16 0x306E=0x9010
# sudo ./MDCDebugger pixreg16 0x306E=0x4810

# Set test_pattern_mode
# 0: Normal operation (generate output data from pixel array)
# 1: Solid color test pattern.
# 2: Full color bar test pattern
# 3: Fade-to-gray color bar test pattern
# 256: Walking 1s test pattern (12 bit)
sudo ./MDCDebugger pixreg16 0x3070=0x0001

# Set test_data_red
sudo ./MDCDebugger pixreg16 0x3072=0x0000

# Set test_data_greenr
sudo ./MDCDebugger pixreg16 0x3074=0x0000

# Set test_data_blue
sudo ./MDCDebugger pixreg16 0x3076=0x0000

# Set test_data_greenb
sudo ./MDCDebugger pixreg16 0x3078=0x0000

# Set row_speed
# 0 cycle delay             = 0x0000
# 1/2 cycle delay (default) = 0x0010
# sudo ./MDCDebugger pixreg16 0x3028=0x0000
sudo ./MDCDebugger pixreg16 0x3028=0x0010

# # Set the x-start address
# # Default = 0x0006
# sudo ./MDCDebugger pixreg16 0x3004=0x000e
#
# # Set the x-end address
# # Default = 0x0905
# sudo ./MDCDebugger pixreg16 0x3008=0x0900
# 
# # Set the y-end address
# # Default = 0x058b
# sudo ./MDCDebugger pixreg16 0x3006=0x007C

# Implement "Recommended Default Register Changes and Sequencer"
sudo ./MDCDebugger pixreg16 0x3ED2=0x0146
sudo ./MDCDebugger pixreg16 0x3EDA=0x88BC
sudo ./MDCDebugger pixreg16 0x3EDC=0xAA63
sudo ./MDCDebugger pixreg16 0x305E=0x00A0

# Start streaming
# (Previous value of 0x301A is 0x10D8, as set above)
sudo ./MDCDebugger pixreg16 0x301A=0x10DC

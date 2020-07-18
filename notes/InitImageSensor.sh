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
# Default = 0x9010
# Fastest = 0xFC10
sudo ./MDCDebugger pixreg16 0x306E=0x9010

# Implement "Recommended Default Register Changes and Sequencer"
sudo ./MDCDebugger pixreg16 0x3ED2=0x0146
sudo ./MDCDebugger pixreg16 0x3EDA=0x88BC
sudo ./MDCDebugger pixreg16 0x3EDC=0xAA63
sudo ./MDCDebugger pixreg16 0x305E=0x00A0

# Start streaming
# (Previous value of 0x301A is 0x10D8, as set above)
sudo ./MDCDebugger pixreg16 0x301A=0x10DC

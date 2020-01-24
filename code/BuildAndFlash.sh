#!/bin/bash
set -e

if [ "$#" -ne 2 ]; then
	echo "Usage:"
    echo "  BuildAndFlash.sh <DeviceType> <ProjName>"
	echo "    DeviceType: 1k (iCEstick) or 8k (iCE40HX board)"
	
	echo
	echo "Examples:"
	echo "  BuildAndFlash.sh 1k IcestickTest_SDRAMReadWriteRandomly"
	echo "  BuildAndFlash.sh 8k IceboardTest_Blinky"
	exit 1
fi

dev="$1"
proj="$2"

# Synthesize the design from Verilog (.sv -> .blif)
yosys -p "synth_ice40 -top "$proj" -blif $proj/top.blif" "$proj/top.sv"

# Place and route the design ({.pcf, .blif} -> .asc)
arachne-pnr -d "$dev" -o "$proj/top.asc" -p "$proj/pins.pcf" "$proj/top.blif"

# Generate the bitstream file (.asc -> .bin)
icepack "$proj/top.asc" "$proj/top.bin"

# Flash the bitstream (.bin)
iceprog "$proj/top.bin"

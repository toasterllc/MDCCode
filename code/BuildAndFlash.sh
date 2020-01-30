#!/bin/bash
set -e

if [ "$#" -ne 3 ]; then
	echo "Usage:"
    echo "  BuildAndFlash.sh <DeviceType> <DevicePackage> <ProjName>"
	echo "    DeviceType: 1k (iCEstick) or 8k (iCE40HX board)"
	echo "    DevicePackage: tq144 (iCEstick) or ct256 (iCE40HX board)"
	
	echo
	echo "Examples:"
	echo "  BuildAndFlash.sh 1k tq144 IcestickTest_SDRAMReadWriteRandomly"
	echo "  BuildAndFlash.sh 8k ct256 IceboardTest_Blinky"
	exit 1
fi

dev="$1"
pkg="$2"
proj="$3"

mkdir -p "$proj/tmp"
cd "$proj/tmp"

# Synthesize the design from Verilog (.v -> .json)
yosys -p "synth_ice40 -top $proj -json top.json" ../top.v

# Place and route the design ({top.json, pins.pcf} -> .asc)
nextpnr-ice40 "--hx$dev" --package "$pkg" --json top.json --pcf ../pins.pcf --asc top.asc # --pcf-allow-unconstrained

# Generate the bitstream file (.asc -> .bin)
icepack top.asc top.bin

# Flash the bitstream (.bin)
iceprog top.bin

#!/bin/bash
set -e

if [ "$#" -ne 3 ]; then
	echo "Usage:"
    echo "  BuildAndFlash.sh <DeviceType> <DevicePackage> <ProjName>"
	echo "    DeviceType: 1k (iCEstick) or 8k (iCE40HX board)"
	echo "    DevicePackage: tq144 (iCEstick) or ct256 (iCE40HX board)"
	
	echo
	echo "Examples:"
	echo "  BuildAndFlash.sh 1k tq144 Icestick_SDRAMReadWriteRandomly"
	echo "  BuildAndFlash.sh 8k ct256 Iceboard_Blinky"
	exit 1
fi

dir=$(cd $(dirname "$0"); pwd)
dev="$1"
pkg="$2"
proj="$3"

rm -Rf "$proj/tmp"
mkdir -p "$proj/tmp"
cp "$dir/Synth.ys" "$proj/tmp"
cp -R "$dir/Util/." "$proj/tmp"
cp "$proj/Top.v" "$proj/tmp"
cp "$proj/Pins.pcf" "$proj/tmp"
cd "$proj/tmp"

# Synthesize the design from Verilog (.v -> .json)
yosys -s Synth.ys Top.v

# Place and route the design ({Top.json, Pins.pcf} -> .asc)
nextpnr-ice40 -r "--hx$dev" --package "$pkg" --json Top.json --pcf ../Pins.pcf --asc Top.asc --pcf-allow-unconstrained --top Top

# Generate the bitstream file (.asc -> .bin)
icepack Top.asc Top.bin

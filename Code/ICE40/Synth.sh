#!/bin/bash
set -e

if [ "$#" -ne 3 ]; then
	echo "Usage:"
    echo "  Synth.sh <DeviceType> <DevicePackage> <ProjName>"
	echo "    DeviceType: 1k (iCEstick), 8k (MDC Rev4, iCE40HX board)"
	echo "    DevicePackage: tq144 (iCEstick), bg121:4k (MDC Rev4), ct256 (iCE40HX board)"
	
	echo
	echo "Examples:"
	echo "  Synth.sh 8k bg121:4k Blinky # MDC Rev4"
	echo "  Synth.sh 1k tq144 Blinky # iCEstick"
	echo "  Synth.sh 8k ct256 Blinky # iCE40HX board"
	exit 1
fi

dir=$(cd $(dirname "$0"); pwd)
dev="$1"
pkg="$2"
proj="$3"

rm -Rf "$proj/tmp"
mkdir -p "$proj/tmp"
cp "$dir/Synth.ys" "$proj/tmp"
cp -R "$dir/Shared/." "$proj/tmp"
cp "$proj/Top.v" "$proj/tmp"
cp "$dir/Pins.pcf" "$proj/tmp"
cd "$proj/tmp"

# Synthesize the design from Verilog (.v -> .json)
yosys -s Synth.ys Top.v

# Place and route the design ({Top.json, Pins.pcf} -> .asc)
nextpnr-ice40 -r "--hx$dev" --package "$pkg" --json Top.json --pcf Pins.pcf --asc Top.asc --pcf-allow-unconstrained --top Top

# Generate the bitstream file (.asc -> .bin)
icepack Top.asc Top.bin

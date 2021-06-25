#!/bin/bash
set -e

if [ "$#" -ne 3 ]; then
	echo "Usage:"
    echo "  Synth.sh <DeviceType> <DevicePackage> <ProjName>"
	echo "    DeviceType: hx1k (iCEstick), hx8k (MDC Rev4, iCE40HX board)"
	echo "    DevicePackage: tq144 (iCEstick), bg121:4k (MDC Rev4), ct256 (iCE40HX board)"
	
	echo
	echo "Examples:"
	echo "  Synth.sh hx8k bg121:4k Blinky # MDC Rev4"
	echo "  Synth.sh hx1k tq144 Blinky # iCEstick"
	echo "  Synth.sh hx8k ct256 Blinky # iCE40HX board"
	exit 1
fi

rootDir=$(cd $(dirname "$0"); pwd)
dev="$1"
pkg="$2"
proj="$3"

synthDir="$rootDir/$proj/Synth"

# Remove existing synthesis files
# (Delete specific files instead of the whole directory so we don't have to worry about
# some crazy case that causes us to execute `rm -Rf /`.)
rm -f "$synthDir/Top.asc" "$synthDir/Top.bin" "$synthDir/Top.json"
# Create 'Synth' directory
mkdir -p "$synthDir"

# Synthesize the design from Verilog (.v -> .json)
cd "$proj"
yosys -s "$rootDir/Synth.ys"

# Place and route the design ({Top.json, Pins.pcf} -> .asc)
nextpnr-ice40 -r "--$dev" --package "$pkg" --json "$synthDir/Top.json" --pcf "$rootDir/Pins.pcf" --asc "$synthDir/Top.asc" --pcf-allow-unconstrained --top Top

# Generate the bitstream file (.asc -> .bin)
icepack "$synthDir/Top.asc" "$synthDir/Top.bin"

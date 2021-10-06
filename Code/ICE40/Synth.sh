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
if [ ! -n "$rootDir" ]; then echo "Bad rootDir" ; exit 1; fi

dev="$1"
if [ ! -n "$dev" ]; then echo "Bad device" ; exit 1; fi

pkg="$2"
if [ ! -n "$pkg" ]; then echo "Bad package" ; exit 1; fi

proj="$3"
if [ ! -n "$proj" ]; then echo "Bad project name" ; exit 1; fi

# Create 'Synth' directory
synthDir="$rootDir/$proj/Synth"
rm -Rf "$synthDir"
mkdir -p "$synthDir"

# Synthesize the design from Verilog (.v -> .json)
pushd "$proj"
yosys -s "$rootDir/Synth.ys"
popd

# Place and route the design ({Top.json, Pins.pcf} -> .asc)
$rootDir/Nextpnr.sh "$dev" "$pkg" "$proj"

# Generate the bitstream file (.asc -> .bin)
icepack "$synthDir/Top.asc" "$synthDir/Top.bin"

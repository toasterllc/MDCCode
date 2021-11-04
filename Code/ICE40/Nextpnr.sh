#!/bin/bash
set -e

if [ "$#" -lt 3 ]; then
	echo "Usage:"
    echo "  Nextpnr.sh <DeviceType> <DevicePackage> <ProjName> [<OutputASCFilePath>]"
	echo "    DeviceType: hx1k (iCEstick), hx8k (MDC Rev4, iCE40HX board)"
	echo "    DevicePackage: tq144 (iCEstick), bg121:4k (MDC Rev4), ct256 (iCE40HX board)"
	
	echo
	echo "Examples:"
	echo "  Nextpnr.sh hx8k bg121:4k Blinky Top.asc     # MDC Rev4"
	echo "  Nextpnr.sh hx1k tq144 Blinky                # iCEstick"
	echo "  Nextpnr.sh hx8k ct256 Blinky                # iCE40HX board"
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

outputASCFilePath="$4"

args=(
    "--$dev"
    --package                   "$pkg"
    --json                      "$rootDir/$proj/Synth/Top.json"
    --pcf                       "$rootDir/Pins.pcf"
    --randomize-seed
    --pcf-allow-unconstrained
    
    # --placer-heap-alpha         0.4
    # --placer-heap-beta          0.525
    # --placer-heap-critexp       6
    # --placer-heap-timingweight  26
    
    # --placer-heap-alpha         0.225
    # --placer-heap-beta          0.9
    # --placer-heap-critexp       6
    # --placer-heap-timingweight  26
    
    # --placer-heap-alpha         0.125
    # --placer-heap-beta          0.825
    # --placer-heap-critexp       5
    # --placer-heap-timingweight  21
    
    # Parameters generated via:
    #   ./nextpnr-mango.py nextpnr-ice40 --hx8k --package bg121:4k  \
    #     --json Top.json --pcf Pins.pcf --pcf-allow-unconstrained
    
    --placer-heap-alpha         0.275
    --placer-heap-beta          0.575
    --placer-heap-critexp       4
    --placer-heap-timingweight  16
)

if [ ! -z "$outputASCFilePath" ]; then
    args+=(--asc "$outputASCFilePath")
fi

nextpnr-ice40 "${args[@]}"

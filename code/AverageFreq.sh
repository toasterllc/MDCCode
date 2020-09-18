#!/bin/bash
set -e

if [ "$#" -ne 3 ]; then
	echo "Usage:"
    echo "  AverageFreq.sh <DeviceType> <DevicePackage> <ProjName>"
	echo "    DeviceType: 1k (iCEstick) or 8k (iCE40HX board)"
	echo "    DevicePackage: tq144 (iCEstick) or ct256 (iCE40HX board)"
	
	echo
	echo "Examples:"
	echo "  AverageFreq.sh 1k tq144 Icestick_SDRAMReadWriteRandomly"
	echo "  AverageFreq.sh 8k ct256 Iceboard_Blinky"
	exit 1
fi

dir=$(cd $(dirname "$0"); pwd)
dev="$1"
pkg="$2"
proj="$3"

cd "$proj/tmp"

# Place and route the design ({top.json, pins.pcf} -> .asc)
trialCount=20
freqTotal=0
freqMin=99999999
freqMax=0
for (( i=0; i<$trialCount; i++)); do
    freq=$( nextpnr-ice40 -r "--hx$dev" --package "$pkg" --json top.json --pcf ../pins.pcf --asc top.asc --pcf-allow-unconstrained 2>&1 | grep 'Info: Max frequency for clock.*sd_clk$SB_IO_OUT_$glb_clk' | tail -1 | cut -d " " -f 8 )
    freqTotal=$( echo "scale=4; $freqTotal+$freq" | bc )
    
    if (($(echo "$freq < $freqMin" | bc))); then
        freqMin="$freq"
    fi
    
    if (($(echo "$freq > $freqMax" | bc))); then
        freqMax="$freq"
    fi
done
freqAverage=$( echo "scale=2; $freqTotal/$trialCount" | bc )
echo "    Min frequency: $freqMin"
echo "    Max frequency: $freqMax"
echo "Average frequency: $freqAverage"

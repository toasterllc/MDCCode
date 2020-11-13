#!/bin/bash
set -e

if [ "$#" -ne 5 ]; then
	echo "Usage:"
    echo "  AverageFreq.sh <DeviceType> <DevicePackage> <ProjName> <ClkName> <NumTrials>"
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
clk="$4"
ntrials="$5"

cd "$proj/tmp"

# Place and route the design ({Top.json, Pins.pcf} -> .asc)
freqs=()
for (( i=0; i<$ntrials; i++)); do
    echo "Trial $i"
    output=$( nextpnr-ice40 -r "--hx$dev" --package "$pkg" --json Top.json --pcf ../Pins.pcf --asc Top.asc --pcf-allow-unconstrained 2>&1 | grep "Info: Max frequency for clock.*$clk" || true )
    if [ -z "$output" ]; then
        echo "No clock named $clk"
        exit 1
    fi
    
    freq=$( echo "$output" | tail -1 | awk -F' ' '{print $(NF-5)}' )
    freqs+=($freq)
done

# Sort the frequencies
freqs=($(IFS=$'\n' ; sort -g <<<"${freqs[*]}"))
# echo "Sorted Freqs: " ${freqs[*]}

freqMin=${freqs[0]}
freqMax=${freqs[ntrials-1]}
freqTotal=$(IFS='+'; bc <<< "${freqs[*]}")
freqAverage=$(bc <<< "scale=2; $freqTotal/$ntrials")
freqMedian=${freqs[(ntrials-1)/2]}

echo "    Min frequency: $freqMin"
echo "    Max frequency: $freqMax"
echo "Average frequency: $freqAverage"
echo " Median frequency: $freqMedian"

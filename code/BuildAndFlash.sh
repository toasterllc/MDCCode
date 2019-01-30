#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage:"
    echo "  BuildAndFlash.sh <ProjName>"
	exit 1
fi

proj="$1"

# Synthesize the design from Verilog (.sv -> .blif)
yosys -p "synth_ice40 -top $proj -blif $proj.blif" "$proj.sv"

# Place and route the design ({.pcf, .blif} -> .asc)
arachne-pnr -d 1k -o "$proj.asc" -p "$proj.pcf" "$proj.blif"

# Generate the bitstream file (.asc -> .bin)
icepack "$proj.asc" "$proj.bin"

# Flash the bitstream (.bin)
iceprog "$proj.bin"

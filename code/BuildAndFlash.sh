#!/bin/bash
set -e

proj="Top"

# Synthesize the design from Verilog (.sv -> .blif)
yosys -p "synth_ice40 -top Top -blif $proj.blif" "$proj.sv"

# Place and route the design ({.pcf, .blif} -> .asc)
arachne-pnr -q -d 1k -o "$proj.asc" -p "$proj.pcf" "$proj.blif"

# Generate the bitstream file (.asc -> .bin)
icepack "$proj.asc" "$proj.bin"

# Flash the bitstream (.bin)
iceprog "$proj.bin"

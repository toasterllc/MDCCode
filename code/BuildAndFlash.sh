#!/bin/bash

proj="blink"

# Synthesize the design from Verilog (.sv -> .blif)
yosys -q -p "synth_ice40 -top main -blif $proj.blif" "$proj.sv"

# Place and route the design ({.pcf, .blif} -> .txt)
arachne-pnr -q -d 1k -o "$proj.txt" -p "$proj.pcf" "$proj.blif"

# Generate the bitstream file (.txt -> .bin)
icepack "$proj.txt" "$proj.bin"

# Flash the bitstream (.bin)
iceprog "$proj.bin"

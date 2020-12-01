#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage:"
    echo "  Sim.sh <ProjName>"
	exit 1
fi

dir=$(cd $(dirname "$0"); pwd)
proj="$1"

rm -Rf "$proj/tmp"
mkdir -p "$proj/tmp"
cp -R "$dir/Shared/." "$proj/tmp"
cp "$proj/Top.v" "$proj/tmp"
cp "$proj/Pins.pcf" "$proj/tmp"
cd "$proj/tmp"

# Simulate!
rm -f Top.vvp
iverilog -DSIM -o Top.vvp -g2012 `yosys-config --datdir/ice40/cells_sim.v` Top.v
./Top.vvp

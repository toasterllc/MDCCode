#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage:"
    echo "  BuildAndSimulate.sh <ProjName>"
	exit 1
fi

proj="$1"

rm -Rf "$proj/tmp"
mkdir -p "$proj/tmp"
cp -R "$dir/Util/." "$proj/tmp"
cp "$proj/Top.v" "$proj/tmp"
cp "$proj/Pins.pcf" "$proj/tmp"
cd "$proj/tmp"

# Simulate!
rm -f Top.vvp
iverilog -DSIM -o Top.vvp -g2012 Top.v
./Top.vvp

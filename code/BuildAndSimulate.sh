#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage:"
    echo "  BuildAndSimulate.sh <ProjName>"
	exit 1
fi

proj="$1"
mkdir -p "$proj/tmp"
cd "$proj/tmp"

# iverilog only allows .v files, so copy top.sv to tmp/top.v and use that
cp ../top.sv top.v

# Simulate!
rm -f top.vvp
iverilog "-I./.." -DSIM -o top.vvp -g2012 top.v
./top.vvp

#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage:"
    echo "  BuildAndSimulate.sh <ProjName>"
	exit 1
fi

proj="$1"

rm -f "$proj.vvp"
iverilog -o "$proj.vvp" -g2012 "$proj.v"
./"$proj.vvp"

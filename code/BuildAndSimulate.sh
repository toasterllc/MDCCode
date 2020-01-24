#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage:"
    echo "  BuildAndSimulate.sh <ProjName>"
	exit 1
fi

proj="$1"

rm -f "$proj/top.vvp"
iverilog -o "$proj/top.vvp" -g2012 "$proj/top.v"
./"$proj/top.vvp"

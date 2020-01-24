#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage:"
    echo "  BuildAndSimulate.sh <ProjName>"
	exit 1
fi

proj="$1"
cd "$proj"

rm -f "top.vvp"
iverilog -o "top.vvp" -g2012 "top.v"
./"top.vvp"

#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  Sim.sh <ProjName>"
    exit 1
fi

rootDir=$(cd $(dirname "$0"); pwd)
if [ ! -n "$rootDir" ]; then echo "Bad rootDir" ; exit 1; fi

proj="$1"
if [ ! -n "$proj" ]; then echo "Bad project name" ; exit 1; fi

# Create 'Sim' directory
simDir="$rootDir/$proj/Sim"
rm -Rf "$simDir"
mkdir -p "$simDir"

# Simulate!
cd "$simDir"
iverilog "-I$rootDir" "-I$rootDir/Shared" -DSIM -o Top.vvp -g2012 -DNO_ICE40_DEFAULT_ASSIGNMENTS "$rootDir/../../Tools/yosys/install/share/yosys/ice40/cells_sim.v" ../Top.v
./Top.vvp

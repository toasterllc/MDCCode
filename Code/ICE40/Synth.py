#!/usr/bin/env python3
import os
import argparse
import shutil
import subprocess



argsp = argparse.ArgumentParser()
argsp.add_argument('--dev', required=True, type=str, help="Device")
argsp.add_argument('--pkg', required=True, type=str, help="Package")
argsp.add_argument('--proj', required=True, type=str, help="Project")
argsp.add_argument('--nosynth', action='store_true', help="Skip synthesis")
argsp.add_argument('--opt', action='store_true', help="Optimize place and route by performing simulated annealing")
args = argsp.parse_args()

rootDir = os.path.dirname(os.path.realpath(__file__))
projDir = os.path.join(rootDir, args.proj)
synthDir = os.path.join(projDir, 'Synth')

if not args.nosynth:
    # Re-create 'Synth' directory
    shutil.rmtree(synthDir, ignore_errors=True)
    os.mkdir(synthDir)
    
    # Synthesize the Veriog design with `yosys` (Top.v -> Top.json)
    subprocess.run(['yosys', '-s', os.path.join(rootDir, 'Synth.ys')], cwd=projDir)




# Place and Route with `nextpnr` ({Top.json, Pins.pcf} -> Top.asc)
nextpnrArgs = [
    'nextpnr-ice40',
    f'--{args.dev}',
    '--package', args.pkg,
    '--json', os.path.join(synthDir, 'Top.json'),
    '--pcf', os.path.join(rootDir, 'Pins.pcf'),
    '--pcf-allow-unconstrained',
    '--asc', os.path.join(synthDir, 'Top.asc'),
]

subprocess.run(nextpnrArgs)

# Generate bitstream file with `icepack` (Top.asc -> Top.bin)
subprocess.run([
    'icepack',
    os.path.join(synthDir, 'Top.asc'),
    os.path.join(synthDir, 'Top.bin'),
])

# Place and route the design ({Top.json, Pins.pcf} -> .asc)
# outputASCFilePath="$4"
#
# args=(
#     "--$dev"
#     --package                   "$pkg"
#     --json                      "$rootDir/$proj/Synth/Top.json"
#     --pcf                       "$rootDir/Pins.pcf"
#     # --randomize-seed
#     --pcf-allow-unconstrained
#
#     ${projNextpnrArgs[@]}
# )
#
# if [ ! -z "$outputASCFilePath" ]; then
#     args+=(--asc "$outputASCFilePath")
# fi
#
# nextpnr-ice40 "${args[@]}"



# # Synthesize the design from Verilog (.v -> .json)
# pushd "$proj"
# yosys -s "$rootDir/Synth.ys"
# popd
#
# # Place and route the design ({Top.json, Pins.pcf} -> .asc)
# $rootDir/Nextpnr.sh "$dev" "$pkg" "$proj" "$synthDir/Top.asc"
#
# # Generate the bitstream file (.asc -> .bin)
# icepack "$synthDir/Top.asc" "$synthDir/Top.bin"






# rm -Rf "$synthDir"
# mkdir -p "$synthDir"

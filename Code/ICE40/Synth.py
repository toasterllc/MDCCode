#!/usr/bin/env python3
import os
import argparse
import shutil
import subprocess
import sys
import ast
import pprint

sys.path.append(os.path.join(os.path.dirname(__file__), "../../Tools/Python"))
from mango import Tuner, scheduler

def nextpnr(cmdArgs, stdoutSuppress=False):
    cmdArgs = [
        'nextpnr-ice40',
        f'--{args.dev}',
        '--package', args.pkg,
        '--json', topJsonFile,
        '--pcf', pinsFile,
        '--pcf-allow-unconstrained',
    ] + cmdArgs
    
    proc = subprocess.Popen(cmdArgs, encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines = []
    while proc.poll() is None:
        line = proc.stdout.readline()
        lines.append(line)
        if not stdoutSuppress:
            print(line, end='')
    return lines

def evalFile(path):
    try:
        with open(path) as f:
            return ast.literal_eval(f.read())
    except OSError:
        return []

def nextpnrParseClkFreq(line):
    if "Info: Max frequency for clock" in line:
        clkName = line.split()[5].replace('\'','').replace(':','')
        clkFreq = float(line.split()[6])
        return (clkName, clkFreq)
    return None

def nextpnrParseClkFreqs(lines):
    parsed = []
    for line in lines:
        clkNameFreq = nextpnrParseClkFreq(line)
        if clkNameFreq is None:
            continue
        parsed.append(clkNameFreq)
    
    assert (len(parsed) % 2) == 0 # There should be 2 matching lines for each clock
    parsed = parsed[int(len(parsed)/2):] # We want the second set of matching lines
    
    clkFreqs = {}
    for clkNameFreq in parsed:
        clkName, freq = clkNameFreq
        clkFreqs[clkName] = freq
    
    return clkFreqs

@scheduler.parallel(n_jobs=-1)
def nextpnrOptTrial(alpha, beta, critexp, timingweight):
    lines = nextpnr([
        '--placer-heap-alpha',          str(alpha),
        '--placer-heap-beta',           str(beta),
        '--placer-heap-critexp',        str(critexp),
        '--placer-heap-timingweight',   str(timingweight),
    ], stdoutSuppress=True)
    
    clkFreqs = nextpnrParseClkFreqs(lines)
    
    # Delete clocks that we don't care about
    for clkName in list(clkFreqs.keys()):
        if clkName not in clocks:
            del clkFreqs[clkName]
    
    clkMin = 130.0
    
    # Subtract the minimum clock
    for clkName in clkFreqs:
        clkFreqs[clkName] -= clkMin
    
    loss = 0.0
    for clkName in clkFreqs:
        loss += clkFreqs[clkName]
    
    return loss

def opt():
    space = {
        'alpha':        [x * .025 for x in range( 1,21)], # 0.025->0.5 (.25 step)
        'beta':         [x * .025 for x in range(20,41)], # 0.500->1.0 (.25 step)
        'critexp':      range(1,11, 1),
        'timingweight': range(1,35, 5),
    }
    
    cfg = dict(num_iteration=1)
    tuner = Tuner(space, nextpnrOptTrial, cfg)
    results = tuner.maximize()
    
    best = results['best_params']
    return [
        '--placer-heap-alpha',          str(best['alpha']),
        '--placer-heap-beta',           str(best['beta']),
        '--placer-heap-critexp',        str(best['critexp']),
        '--placer-heap-timingweight',   str(best['timingweight']),
    ]

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
topAscFile = os.path.join(synthDir, 'Top.asc')
topBinFile = os.path.join(synthDir, 'Top.bin')
topJsonFile = os.path.join(synthDir, 'Top.json')
pinsFile = os.path.join(rootDir, 'Pins.pcf')
clocksFile = os.path.join(projDir, 'Clocks.py')
nextpnrArgsFile = os.path.join(projDir, 'NextpnrArgs.py')

# Synthesize the Veriog design with `yosys` (Top.v -> Top.json)
if not args.nosynth:
    print('\n# Synthesizing design\n')
    
    # Re-create 'Synth' directory
    shutil.rmtree(synthDir, ignore_errors=True)
    os.mkdir(synthDir)

    subprocess.run(['yosys', '-s', os.path.join(rootDir, 'Synth.ys')], cwd=projDir)

# Optimize the design
if args.opt:
    print('\n# Optimizing design\n')
    
    clocks = evalFile(clocksFile)
    if not clocks:
        print(f"{clocksFile} doesn't exist or doesn't contain any clocks")
        sys.exit(1)
    
    bestArgs = opt()
    
    # Write the 'NextpnrArgs.py' file
    with open(nextpnrArgsFile, 'w') as f:
        f.write(pprint.pformat(bestArgs))

# Place and Route with `nextpnr` ({Top.json, Pins.pcf} -> Top.asc)
print('\n# Placing/routing design\n')
nextpnrArgs = [ '--asc', topAscFile ] + evalFile(nextpnrArgsFile)
lines = nextpnr(nextpnrArgs)
clkFreqs = nextpnrParseClkFreqs(lines)

print('')
print('')
print(args.proj)
print('')
print('==========================================================')
print('Clk                                                   Freq')
print('----------------------------------------------------------')

for clkName in sorted(clkFreqs):
    print(f'{clkName:50} {clkFreqs[clkName]:8.2f}')

# Generate bitstream file with `icepack` (Top.asc -> Top.bin)
print('\n# Packing design\n')
subprocess.run([ 'icepack', topAscFile, topBinFile ])

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

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
    nextpnrPath = os.path.join(rootDir, '../../Tools/nextpnr/install/bin/nextpnr-ice40')
    cmdArgs = [
        nextpnrPath,
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
        if clkName not in projClocks:
            del clkFreqs[clkName]
    
    clkMin = 130
    
    # Subtract the minimum clock
    for clkName in clkFreqs:
        delta = (clkFreqs[clkName] - clkMin)
        # Magnify frequencies less than the minimum
        if delta < 0:
            delta *= 10
        clkFreqs[clkName] = delta
    
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
    
    cfg = dict(num_iteration=10)
    tuner = Tuner(space, nextpnrOptTrial, cfg)
    results = tuner.maximize()
    
    best = results['best_params']
    return [
        '--placer-heap-alpha',          str(best['alpha']),
        '--placer-heap-beta',           str(best['beta']),
        '--placer-heap-critexp',        str(best['critexp']),
        '--placer-heap-timingweight',   str(best['timingweight']),
    ]

def commentedStr(s):
    return "# " + "\n# ".join(s.splitlines())

argsp = argparse.ArgumentParser()
argsp.add_argument('--dev', required=True, type=str, help="Device")
argsp.add_argument('--pkg', required=True, type=str, help="Package")
argsp.add_argument('--proj', required=True, type=str, help="Project")
argsp.add_argument('--nosynth', action='store_true', help="Skip synthesis")
argsp.add_argument('--opt', action='store_true', help="Optimize place and route")
args = argsp.parse_args()

rootDir = os.path.dirname(os.path.realpath(__file__))
projDir = os.path.join(rootDir, args.proj)
synthDir = os.path.join(projDir, 'Synth')
topAscFile = os.path.join(synthDir, 'Top.asc')
topBinFile = os.path.join(synthDir, 'Top.bin')
topJsonFile = os.path.join(synthDir, 'Top.json')
pinsFile = os.path.join(rootDir, 'Pins.pcf')
projClocksFile = os.path.join(projDir, 'Clocks.py')
nextpnrArgsFile = os.path.join(projDir, 'NextpnrArgs.py')

# Synthesize the Veriog design with `yosys` (Top.v -> Top.json)
if not args.nosynth:
    print('\n# [Synth.py] Synthesizing design\n')
    
    # Re-create 'Synth' directory
    shutil.rmtree(synthDir, ignore_errors=True)
    os.mkdir(synthDir)

    yosysPath = os.path.join(rootDir, '../../Tools/yosys/install/bin/yosys')
    subprocess.run([yosysPath, '-s', os.path.join(rootDir, 'Synth.ys')], cwd=projDir)

# Optimize the design
projClocks = evalFile(projClocksFile)
if args.opt:
    print('\n# [Synth.py] Optimizing design\n')
    if not projClocks:
        print(f"[Synth.py] {projClocksFile} doesn't exist or doesn't contain any clocks")
        sys.exit(1)
    
    nextpnrProjArgs = opt()

# If we didn't optimize the design, load nextpnr args from the project's NextpnrArgs.py file
else:
    nextpnrProjArgs = evalFile(nextpnrArgsFile)

# Place and Route with `nextpnr` ({Top.json, Pins.pcf} -> Top.asc)
print('\n# [Synth.py] Placing/routing design\n')
nextpnrArgs = [ '--asc', topAscFile ] + nextpnrProjArgs
lines = nextpnr(nextpnrArgs)
clkFreqs = nextpnrParseClkFreqs(lines)
clkStatsStr = f"""* {args.proj}
-----------------------------------------------------------
Clk                                                    Freq
-----------------------------------------------------------
"""

for clkName in sorted(clkFreqs):
    marking = "*" if clkName in projClocks else ""
    clkStatsStr += f'{clkName:50} {clkFreqs[clkName]:8.2f} {marking}\n'

print('')
print(clkStatsStr)

# Write the 'NextpnrArgs.py' file (if we optimized the design)
if args.opt:
    with open(nextpnrArgsFile, 'w') as f:
        f.write(commentedStr(clkStatsStr))
        f.write('\n\n')
        f.write(pprint.pformat(nextpnrProjArgs))
        f.write('\n')

# Generate bitstream file with `icepack` (Top.asc -> Top.bin)
print('\n# [Synth.py] Packing design\n')
icepackPath = os.path.join(rootDir, '../../Tools/icestorm/install/bin/icepack')
subprocess.run([ icepackPath, '-Fh', topAscFile, topBinFile ])

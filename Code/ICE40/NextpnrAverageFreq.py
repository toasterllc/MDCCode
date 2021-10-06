#!/usr/bin/env python3
import sys
import os
import multiprocessing
import subprocess
import re
import random
import statistics

if len(sys.argv) != 5:
    print("Usage:")
    print("  NextpnrAverageFreq.py <DeviceType> <DevicePackage> <ProjName> <NumTrials>")
    print("    DeviceType: hx1k (iCEstick), hx8k (MDC Rev4, iCE40HX board)")
    print("    DevicePackage: tq144 (iCEstick), bg121:4k (MDC Rev4), ct256 (iCE40HX board)")
    print("")
    print("Examples:")
    print("  NextpnrAverageFreq.py hx8k bg121:4k Blinky 'clk$glb_clk' 51")
    print("  NextpnrAverageFreq.py hx1k tq144 Blinky 'clk$glb_clk' 51")
    print("  NextpnrAverageFreq.py hx8k ct256 Blinky 'clk$glb_clk' 51")
    sys.exit(1)

scriptDir = os.path.dirname(os.path.abspath(sys.argv[0]))
dev = sys.argv[1]
pkg = sys.argv[2]
proj = sys.argv[3]
ntrials = int(sys.argv[4])

projDirPath = os.path.join(scriptDir, proj)
topFilePath = os.path.join(projDirPath, "Synth", "Top.json")
pcfFilePath = os.path.join(scriptDir, "Pins.pcf")

synthProg = 'Synth.sh'
synthArgs = [os.path.join(scriptDir, synthProg), dev, pkg, proj]

pnrProg = 'nextpnr-ice40'
pnrArgs = [
    pnrProg,
    '--'+dev,
    '--package', pkg,
    '--json', topFilePath,
    '--pcf', pcfFilePath,
    '--pcf-allow-unconstrained',
    '--placer-heap-alpha', '0.025',
    '--placer-heap-beta', '0.5',
    '--placer-heap-critexp', '3',
    '--placer-heap-timingweight', '11',
]

# Print iterations progress
def printProgress(iteration, total, prefix = '', suffix = '', decimals = 1, length = 100, fill = '█', printEnd = "\r"):
    """
    Call in a loop to create terminal progress bar
    @params:
        iteration   - Required  : current iteration (Int)
        total       - Required  : total iterations (Int)
        prefix      - Optional  : prefix string (Str)
        suffix      - Optional  : suffix string (Str)
        decimals    - Optional  : positive number of decimals in percent complete (Int)
        length      - Optional  : character length of bar (Int)
        fill        - Optional  : bar fill character (Str)
        printEnd    - Optional  : end character (e.g. "\r", "\r\n") (Str)
    """
    percent = ("{0:." + str(decimals) + "f}").format(100 * (iteration / float(total)))
    filledLength = int(length * iteration // total)
    bar = fill * filledLength + '-' * (length - filledLength)
    print(f'\r{prefix} |{bar}| {percent}% {suffix}', end = printEnd)
    # Print New Line on Complete
    if iteration == total: 
        print()

def executeTrial(_):
    proc = None
    while True:
        cmd = pnrArgs + ['--seed', str(random.randint(-0x80000000,0x7FFFFFFF))]
        try:
            # Sometimes nextpnr hangs, so if that happens, try executing it again.
            # (It seems that certain seed values deterministically cause a hang,
            # so we use a different seed for each attempt.)
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        except subprocess.TimeoutExpired:
            print(f"{pnrProg} inovcation timed out: {' '.join(cmd)}\n")
            continue
        break
    
    proc.check_returncode()
    outputLines = proc.stdout.decode("utf-8").splitlines()
    
    # nextpnr should output 2 lines matching this 'Max frequency for clock' string, for each clock.
    # We want the second set of matching strings, which is after nextpnr routes the design.
    p = re.compile('.*: Max frequency for clock.*')
    clkLines = [ s for s in outputLines if p.match(s) ]
    assert (len(clkLines) % 2) == 0 # There should be 2 matching lines for each clock
    clkLines = clkLines[int(len(clkLines)/2):] # We want the second set of matching lines
    
    clkFreqs = {}
    for clkLine in clkLines:
        parts = clkLine.split("'")
        assert len(parts) == 3
        clkName = parts[1]
        
        parts = [ s.strip() for s in clkLine.split(':') ]
        assert len(parts) == 3
        
        parts = parts[2].split(' ')
        assert len(parts) >= 2
        assert parts[1] == 'MHz'
        clkFreq = float(parts[0])
        
        clkFreqs[clkName] = clkFreq
    
    return clkFreqs

# Synthesize the design with Synth.sh, since it might be out-of-date
print(f"Synthesizing design ({synthProg} {' '.join(synthArgs[1:])})\n")
proc = subprocess.run(synthArgs, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if proc.returncode != 0:
    raise RuntimeError(f'{synthProg} failed')

print(f"Routing design with {ntrials} trials ({' '.join(pnrArgs)})\n")
clkFreqs = {}
pool = multiprocessing.Pool(multiprocessing.cpu_count())
for i, f in enumerate(pool.imap_unordered(executeTrial, range(ntrials)), 1):
    for clkName in f:
        clkFreq = f[clkName]
        if clkName not in clkFreqs:
            clkFreqs[clkName] = [clkFreq]
        else:
            clkFreqs[clkName].append(clkFreq)
    printProgress(i, ntrials)

print('')
print('')
print('======================================================================================')
print(f'Clk                                                   Min      Max      Avg      Med')
print('--------------------------------------------------------------------------------------')

for clk in sorted(clkFreqs):
    freqs = clkFreqs[clk]
    freqMin = min(freqs)
    freqMax = max(freqs)
    freqAverage = statistics.mean(freqs)
    freqMedian = statistics.median(freqs)
    
    print(f'{clk:50} {freqMin:8.2f} {freqMax:8.2f} {freqAverage:8.2f} {freqMedian:8.2f}')

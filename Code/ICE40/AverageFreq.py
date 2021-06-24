#!/usr/bin/env python3
import sys
import os
import multiprocessing
import subprocess
import re
import random
import statistics

if len(sys.argv) != 6:
    print("Usage:")
    print("  AverageFreq.py <DeviceType> <DevicePackage> <ProjName> <ClkName> <NumTrials>")
    print("    DeviceType: hx1k (iCEstick) or hx8k (iCE40HX board)")
    print("    DevicePackage: tq144 (iCEstick) or ct256 (iCE40HX board)")
    print("")
    print("Examples:")
    print("  AverageFreq.py hx1k tq144 Icestick_SDRAMReadWriteRandomly 'pix_dclk$SB_IO_IN_$glb_clk' 51")
    print("  AverageFreq.py hx8k ct256 Iceboard_Blinky 'pix_dclk$SB_IO_IN_$glb_clk' 51")
    sys.exit(1)

scriptDir = os.path.dirname(os.path.abspath(sys.argv[0]))
dev = sys.argv[1]
pkg = sys.argv[2]
proj = sys.argv[3]
clkName = sys.argv[4]
ntrials = int(sys.argv[5])

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
    projDirPath = os.path.join(scriptDir, proj)
    topFilePath = os.path.join(projDirPath, "tmp", "Top.json")
    pcfFilePath = os.path.join(scriptDir, "Pins.pcf")
    
    cmd = [
        'nextpnr-ice40',
        '--seed',
        str(random.randint(-0x80000000,0x7FFFFFFF)),
        '--'+dev,
        '--package',
        pkg,
        '--json',
        topFilePath,
        '--pcf',
        pcfFilePath,
        '--pcf-allow-unconstrained',
    ]
    
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    outputLines = proc.stdout.decode("utf-8").splitlines()
    
    # nextpnr should output 2 lines matching the clock string (and we want the second one)
    p = re.compile('.*: Max frequency for clock.*'+re.escape(clkName))
    clkLines = [ s for s in outputLines if p.match(s) ]
    
    assert len(clkLines) == 2
    clkLine = clkLines[1]
    
    parts = [ s.strip() for s in clkLine.split(':') ]
    assert len(parts) == 3
    
    parts = parts[2].split(' ')
    assert len(parts) >= 2
    assert parts[1] == 'MHz'
    freq = float(parts[0])
    
    return freq

freqs = []
pool = multiprocessing.Pool(multiprocessing.cpu_count())
for i, f in enumerate(pool.imap_unordered(executeTrial, range(ntrials)), 1):
    freqs.append(f)
    printProgress(i, ntrials)

freqMin = min(freqs)
freqMax = max(freqs)
freqAverage = statistics.mean(freqs)
freqMedian = statistics.median(freqs)

print('==========================================')
print(f'    Min frequency: {freqMin:.2f}')
print(f'    Max frequency: {freqMax:.2f}')
print(f'Average frequency: {freqAverage:.2f}')
print(f' Median frequency: {freqMedian:.2f}')

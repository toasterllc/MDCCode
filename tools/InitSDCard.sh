#!/bin/bash

# Get path to MDCDebugger
dir=$(cd $(dirname "$0"); pwd)
MDCDebugger="$dir/MDCDebugger/MDCDebugger"

# CMD0
"$MDCDebugger" sdcmd CMD0 0x00000000

# CMD8
#   Voltage level = 2.7-3.6V
#   Check pattern = 10101010 (spec: "It is recommended to use '10101010b' for the 'check pattern'")
"$MDCDebugger" sdcmd CMD8 0x000001AA R7

# CMD55
"$MDCDebugger" sdcmd CMD55 0x00000000 R1


#!/bin/bash

# Get path to MDCDebugger
dir=$(cd $(dirname "$0"); pwd)
MDCDebugger="$dir/MDCDebugger/MDCDebugger"

# CMD0 (GO_IDLE_STATE: go to idle state)
#   State: X -> Idle
"$MDCDebugger" sdcmd CMD0 0x00000000

# CMD8 (SEND_IF_COND: send interface condition)
#   State: Idle -> Idle
#   Voltage level = 2.7-3.6V
#   Check pattern = 10101010 (spec: "It is recommended to use '10101010b' for the 'check pattern'")
"$MDCDebugger" sdcmd CMD8 0x000001AA R7

for i in {1..2}; do
    # CMD55 (APP_CMD: app-specific command follows)
    #   State: no change
    "$MDCDebugger" sdcmd CMD55 0x00000000 R1
    
    # ACMD41 (SD_SEND_OP_COND: initialize)
    #   State: Idle -> Ready
    #   HCS = 1 (SDHC/SDXC supported)
    #   XPC = 1 (maximum performance)
    #   S18R = 0 (continue with current signalling voltage -- for A2 cards hopefully we don't need to do anything else?)
    #   Vdd Voltage Window = 0x8000 = 2.7-2.8V ("OCR Register Definition")
    "$MDCDebugger" sdcmd CMD41 0x50008000 R3
done



# CMD2 (ALL_SEND_CID: get card identification number (CID))
#   State: Ready -> Identification
"$MDCDebugger" sdcmd CMD2 0x00000000 R2

# CMD3 (SEND_RELATIVE_ADDR: ask card to publish a new relative address (RCA))
#   State: Identification -> Standby
"$MDCDebugger" sdcmd CMD3 0x00000000 R6

# CMD7 (SELECT_CARD/DESELECT_CARD: select card)
#   State: Standby -> Transfer
"$MDCDebugger" sdcmd CMD7 0xAAAA0000 R1

# CMD55 (APP_CMD: app-specific command follows)
#   State: no change
"$MDCDebugger" sdcmd CMD55 0xAAAA0000 R1

# ACMD6 (SET_BUS_WIDTH: set bus width to 4 bits)
#   State: Transfer -> Transfer
#   Bus width = 2 (width = 4 bits)
"$MDCDebugger" sdcmd CMD6 0x00000002 R1

# CMD6 (SWITCH_FUNC: switch to SDR104)
#   State: Transfer -> Data
#   Mode = 1 (switch function)
#   Group 6 (Reserved)          = 0xF (no change)
#   Group 5 (Reserved)          = 0xF (no change)
#   Group 4 (Current Limit)     = 0xF (no change)
#   Group 3 (Driver Strength)   = 0xF (no change)
#   Group 2 (Command System)    = 0xF (no change)
#   Group 1 (Access Mode)       = 0x3 (SDR104)
"$MDCDebugger" sdcmd CMD6 0x80FFFFF3 R1

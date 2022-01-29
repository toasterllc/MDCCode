#!/bin/bash
set -e

if [ "$#" -lt 3 ]; then
	echo "Usage:"
    echo "  Nextpnr.sh <DeviceType> <DevicePackage> <ProjName> [<OutputASCFilePath>]"
	echo "    DeviceType: hx1k (iCEstick), hx8k (MDC Rev4, iCE40HX board)"
	echo "    DevicePackage: tq144 (iCEstick), bg121:4k (MDC Rev4), ct256 (iCE40HX board)"
	
	echo
	echo "Examples:"
	echo "  Nextpnr.sh hx8k bg121:4k Blinky Top.asc     # MDC Rev4"
	echo "  Nextpnr.sh hx1k tq144 Blinky                # iCEstick"
	echo "  Nextpnr.sh hx8k ct256 Blinky                # iCE40HX board"
	exit 1
fi

rootDir=$(cd $(dirname "$0"); pwd)
if [ ! -n "$rootDir" ]; then echo "Bad rootDir" ; exit 1; fi

dev="$1"
if [ ! -n "$dev" ]; then echo "Bad device" ; exit 1; fi

pkg="$2"
if [ ! -n "$pkg" ]; then echo "Bad package" ; exit 1; fi

proj="$3"
if [ ! -n "$proj" ]; then echo "Bad project name" ; exit 1; fi

if [ -f "./$proj/NextpnrArgs.sh" ]; then
    . ./$proj/NextpnrArgs.sh
fi
# echo "${projNextpnrArgs[*]}"
# exit 1

outputASCFilePath="$4"

args=(
    "--$dev"
    --package                   "$pkg"
    --json                      "$rootDir/$proj/Synth/Top.json"
    --pcf                       "$rootDir/Pins.pcf"
    # --randomize-seed
    --pcf-allow-unconstrained
    
    ${projNextpnrArgs[@]}
    
    # --placer-heap-alpha         0.4
    # --placer-heap-beta          0.525
    # --placer-heap-critexp       6
    # --placer-heap-timingweight  26
    
    # --placer-heap-alpha         0.225
    # --placer-heap-beta          0.9
    # --placer-heap-critexp       6
    # --placer-heap-timingweight  26
    
    # --placer-heap-alpha         0.125
    # --placer-heap-beta          0.825
    # --placer-heap-critexp       5
    # --placer-heap-timingweight  21
    
    # Parameters generated via:
    #   cd ~/repos/MDC/Code/ICE40/MSPApp/Synth
    #   ~/repos/nextpnr-anneal/tunners/nextpnr-mango.py nextpnr-ice40 --hx8k --package bg121:4k --json Top.json --pcf ../../Pins.pcf --pcf-allow-unconstrained
    
    # --placer-heap-alpha         0.025
    # --placer-heap-beta          0.5
    # --placer-heap-critexp       1
    # --placer-heap-timingweight  8
    
    # ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
    # ICEApp.readoutfifo_r_clk_$glb_clk                    131.96   131.96   131.96   131.96
    # ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23
    # ICEApp.spi_clk_$glb_clk                              103.01   103.01   103.01   103.01
    # ice_img_clk16mhz$SB_IO_IN                            121.21   121.21   121.21   121.21
    # img_dclk$SB_IO_IN_$glb_clk                           137.36   137.36   137.36   137.36
    # ram_clk$SB_IO_OUT_$glb_clk                           122.29   122.29   122.29   122.29
    
    # --placer-heap-alpha         0.425
    # --placer-heap-beta          0.875
    # --placer-heap-critexp       8
    # --placer-heap-timingweight  1
    
    
    
    
    # ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
    # ICEApp.readoutfifo_r_clk_$glb_clk                    135.46   135.46   135.46   135.46
    # ICEApp.sd_clk_int                                    327.55   327.55   327.55   327.55
    # ICEApp.spi_clk_$glb_clk                              113.33   113.33   113.33   113.33
    # ice_img_clk16mhz$SB_IO_IN                            129.80   129.80   129.80   129.80
    # img_dclk$SB_IO_IN_$glb_clk                           126.42   126.42   126.42   126.42
    # ram_clk$SB_IO_OUT_$glb_clk                           137.49   137.49   137.49   137.49
    
    # --placer-heap-alpha         0.075
    # --placer-heap-beta          0.55
    # --placer-heap-critexp       9
    # --placer-heap-timingweight  11
    
    
    
    
    # ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
    # ICEApp.readoutfifo_r_clk_$glb_clk                    126.47   126.47   126.47   126.47
    # ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23
    # ICEApp.spi_clk_$glb_clk                              116.56   116.56   116.56   116.56
    # ice_img_clk16mhz$SB_IO_IN                            123.62   123.62   123.62   123.62
    # img_dclk$SB_IO_IN_$glb_clk                           135.45   135.45   135.45   135.45
    # ram_clk$SB_IO_OUT_$glb_clk                           134.77   134.77   134.77   134.77
    
    # --placer-heap-alpha         0.075
    # --placer-heap-beta          0.55
    # --placer-heap-critexp       9
    # --placer-heap-timingweight  9
    
    
    # ICEAppMSP
    # ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
    # ICEApp.readoutfifo_r_clk_$glb_clk                    132.70   132.70   132.70   132.70
    # ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23
    # ICEApp.spi_clk_$glb_clk                              116.25   116.25   116.25   116.25
    # ice_img_clk16mhz$SB_IO_IN                            120.90   120.90   120.90   120.90
    # img_dclk$SB_IO_IN_$glb_clk                           132.59   132.59   132.59   132.59
    # ram_clk$SB_IO_OUT_$glb_clk                           133.26   133.26   133.26   133.26
    
    # --placer-heap-alpha         0.075
    # --placer-heap-beta          0.55
    # --placer-heap-critexp       9
    # --placer-heap-timingweight  8
    
    
    # ICEAppSDReadoutSTM
    # Clk                                                   Min      Max      Avg      Med
    # --------------------------------------------------------------------------------------
    # ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
    # ICEApp.readoutfifo_prop_clk_$glb_clk                 137.49   137.49   137.49   137.49
    # ICEApp.readoutfifo_r_clk_$glb_clk                     93.21    93.21    93.21    93.21
    # ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23
    # --placer-heap-alpha         0.5
    # --placer-heap-beta          0.675
    # --placer-heap-critexp       9
    # --placer-heap-timingweight  21
)

if [ ! -z "$outputASCFilePath" ]; then
    args+=(--asc "$outputASCFilePath")
fi

nextpnr-ice40 "${args[@]}"

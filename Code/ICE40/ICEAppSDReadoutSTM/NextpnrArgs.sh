# ICEAppSDReadoutSTM
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
# ICEApp.readoutfifo_prop_clk_$glb_clk                 137.49   137.49   137.49   137.49
# ICEApp.readoutfifo_r_clk_$glb_clk                     93.21    93.21    93.21    93.21
# ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23

projNextpnrArgs=(
    --placer-heap-alpha         0.5
    --placer-heap-beta          0.675
    --placer-heap-critexp       9
    --placer-heap-timingweight  21
)

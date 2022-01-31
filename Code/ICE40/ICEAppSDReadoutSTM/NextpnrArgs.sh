# ICEAppSDReadoutSTM
# 
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
# ICEApp.readoutfifo_prop_clk_$glb_clk                 139.65   139.65   139.65   139.65
# ICEApp.readoutfifo_r_clk_$glb_clk                    117.12   117.12   117.12   117.12
# ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23


projNextpnrArgs=(
    --placer-heap-alpha         0.05
    --placer-heap-beta          0.725
    --placer-heap-critexp       2
    --placer-heap-timingweight  11
)

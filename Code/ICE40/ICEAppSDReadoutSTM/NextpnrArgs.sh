# ICEAppSDReadoutSTM
# 
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.SDController.clk_slow                         170.94   170.94   170.94   170.94
# ICEApp.readoutfifo_prop_clk_$glb_clk                 130.75   130.75   130.75   130.75
# ICEApp.readoutfifo_r_clk_$glb_clk                    130.04   130.04   130.04   130.04
# ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23


projNextpnrArgs=(
    --placer-heap-alpha         0.05
    --placer-heap-beta          0.725
    --placer-heap-critexp       2
    --placer-heap-timingweight  11
)

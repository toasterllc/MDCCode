# ICEAppImgCaptureSTM
# 
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    118.40   118.40   118.40   118.40
# ice_img_clk16mhz$SB_IO_IN_$glb_clk                   121.94   121.94   121.94   121.94
# img_dclk$SB_IO_IN_$glb_clk                           130.46   130.46   130.46   130.46
# ram_clk$SB_IO_OUT_$glb_clk                           130.94   130.94   130.94   130.94

projNextpnrArgs=(
    --placer-heap-alpha         0.475
    --placer-heap-beta          0.625
    --placer-heap-critexp       9
    --placer-heap-timingweight  10
)

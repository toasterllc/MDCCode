# ICEAppImgCaptureSTM
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    119.39   119.39   119.39   119.39
# ice_img_clk16mhz$SB_IO_IN_$glb_clk                   126.58   126.58   126.58   126.58
# img_dclk$SB_IO_IN_$glb_clk                           136.84   136.84   136.84   136.84
# ram_clk$SB_IO_OUT_$glb_clk                           126.42   126.42   126.42   126.42

projNextpnrArgs=(
    --placer-heap-alpha         0.5
    --placer-heap-beta          0.675
    --placer-heap-critexp       9
    --placer-heap-timingweight  21
)

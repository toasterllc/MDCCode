# ICEAppImgCaptureSTM
#
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    107.10   107.10   107.10   107.10
# ice_img_clk16mhz$SB_IO_IN_$glb_clk                   122.87   122.87   122.87   122.87
# img_dclk$SB_IO_IN_$glb_clk                           130.40   130.40   130.40   130.40
# ram_clk$SB_IO_OUT_$glb_clk                           133.64   133.64   133.64   133.64

projNextpnrArgs=(
    --placer-heap-alpha         0.425
    --placer-heap-beta          0.575
    --placer-heap-critexp       10
    --placer-heap-timingweight  8
)

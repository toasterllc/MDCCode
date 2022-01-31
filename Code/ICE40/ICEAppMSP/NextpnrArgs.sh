# ICEAppMSP
# 
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
# ICEApp.readoutfifo_r_clk_$glb_clk                    143.49   143.49   143.49   143.49
# ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23
# ICEApp.spi_clk_$glb_clk                              113.33   113.33   113.33   113.33
# ice_img_clk16mhz$SB_IO_IN                            132.84   132.84   132.84   132.84
# img_dclk$SB_IO_IN_$glb_clk                           135.28   135.28   135.28   135.28
# ram_clk$SB_IO_OUT_$glb_clk                           134.77   134.77   134.77   134.77

projNextpnrArgs=(
    --placer-heap-alpha         0.075
    --placer-heap-beta          0.55
    --placer-heap-critexp       9
    --placer-heap-timingweight  16
)

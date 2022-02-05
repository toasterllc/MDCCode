# ICEAppMSP
# 
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.SDController.clk_slow                         176.03   176.03   176.03   176.03
# ICEApp.readoutfifo_r_clk_$glb_clk                    134.07   134.07   134.07   134.07
# ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23
# ICEApp.spi_clk_$glb_clk                              105.30   105.30   105.30   105.30
# ice_img_clk16mhz$SB_IO_IN                            120.11   120.11   120.11   120.11
# img_dclk$SB_IO_IN_$glb_clk                           130.11   130.11   130.11   130.11
# ram_clk$SB_IO_OUT_$glb_clk                           132.40   132.40   132.40   132.40

projNextpnrArgs=(
    --placer-heap-alpha         0.075
    --placer-heap-beta          0.55
    --placer-heap-critexp       9
    --placer-heap-timingweight  17
)

# ICEAppMSP
# ICEApp.SDController.clk_slow                         626.57   626.57   626.57   626.57
# ICEApp.readoutfifo_r_clk_$glb_clk                    132.70   132.70   132.70   132.70
# ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23
# ICEApp.spi_clk_$glb_clk                              116.25   116.25   116.25   116.25
# ice_img_clk16mhz$SB_IO_IN                            120.90   120.90   120.90   120.90
# img_dclk$SB_IO_IN_$glb_clk                           132.59   132.59   132.59   132.59
# ram_clk$SB_IO_OUT_$glb_clk                           133.26   133.26   133.26   133.26

projNextpnrArgs=(
    --placer-heap-alpha         0.075
    --placer-heap-beta          0.55
    --placer-heap-critexp       9
    --placer-heap-timingweight  8
)

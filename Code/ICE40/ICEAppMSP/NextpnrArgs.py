# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    139.57 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              112.88 
# ice_img_clk16mhz$SB_IO_IN                            128.06 
# img_dclk$SB_IO_IN_$glb_clk                           137.65 *
# ram_clk$SB_IO_OUT_$glb_clk                           127.88 *

['--placer-heap-alpha',
 '0.25',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '4',
 '--placer-heap-timingweight',
 '16']

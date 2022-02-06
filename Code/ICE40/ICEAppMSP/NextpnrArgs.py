# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         157.06 
# ICEApp.readoutfifo_r_clk_$glb_clk                    138.56 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              101.56 
# ice_img_clk16mhz$SB_IO_IN                            124.60 
# img_dclk$SB_IO_IN_$glb_clk                           133.39 *
# ram_clk$SB_IO_OUT_$glb_clk                           133.56 *

['--placer-heap-alpha',
 '0.1',
 '--placer-heap-beta',
 '0.5750000000000001',
 '--placer-heap-critexp',
 '3',
 '--placer-heap-timingweight',
 '1']

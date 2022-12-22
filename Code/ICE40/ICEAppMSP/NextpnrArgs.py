# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         186.12 
# ICEApp.readoutfifo_r_clk_$glb_clk                    139.16 *
# ICEApp.sd_clk_int                                    316.06 
# ICEApp.spi_clk_$glb_clk                              112.88 
# ice_img_clk16mhz$SB_IO_IN                            114.78 
# img_dclk$SB_IO_IN_$glb_clk                           146.84 *
# ram_clk$SB_IO_OUT_$glb_clk                           124.53 *

['--placer-heap-alpha',
 '0.17500000000000002',
 '--placer-heap-beta',
 '0.625',
 '--placer-heap-critexp',
 '6',
 '--placer-heap-timingweight',
 '21']

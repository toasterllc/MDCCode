# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    139.84 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              116.28 
# ice_img_clk16mhz$SB_IO_IN                            113.33 
# img_dclk$SB_IO_IN_$glb_clk                           139.65 *
# ram_clk$SB_IO_OUT_$glb_clk                           125.98 *

['--placer-heap-alpha',
 '0.07500000000000001',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '2',
 '--placer-heap-timingweight',
 '16']

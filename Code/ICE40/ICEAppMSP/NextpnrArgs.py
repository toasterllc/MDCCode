# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         223.71 
# ICEApp.readoutfifo_r_clk_$glb_clk                    139.57 *
# ICEApp.sd_clk_int                                    316.06 
# ICEApp.spi_clk_$glb_clk                              119.99 
# ice_img_clk16mhz$SB_IO_IN                            133.17 
# img_dclk$SB_IO_IN_$glb_clk                           150.06 *
# ram_clk$SB_IO_OUT_$glb_clk                           129.33 *

['--placer-heap-alpha',
 '0.05',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '5',
 '--placer-heap-timingweight',
 '26']

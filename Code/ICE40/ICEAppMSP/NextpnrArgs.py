# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    140.11 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              114.14 
# ice_img_clk16mhz$SB_IO_IN                            123.95 
# img_dclk$SB_IO_IN_$glb_clk                           132.66 *
# ram_clk$SB_IO_OUT_$glb_clk                           125.47 *

['--placer-heap-alpha',
 '0.4',
 '--placer-heap-beta',
 '0.525',
 '--placer-heap-critexp',
 '5',
 '--placer-heap-timingweight',
 '21']

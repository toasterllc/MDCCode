# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         160.95 
# ICEApp.readoutfifo_r_clk_$glb_clk                    131.60 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              122.04 
# ice_img_clk16mhz$SB_IO_IN                            132.84 
# img_dclk$SB_IO_IN_$glb_clk                           145.62 *
# ram_clk$SB_IO_OUT_$glb_clk                           129.28 *

['--placer-heap-alpha',
 '0.15000000000000002',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '5',
 '--placer-heap-timingweight',
 '11']

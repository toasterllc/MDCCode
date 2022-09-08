# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         188.32 
# ICEApp.readoutfifo_r_clk_$glb_clk                    133.69 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              122.46 
# ice_img_clk16mhz$SB_IO_IN                            125.69 
# img_dclk$SB_IO_IN_$glb_clk                           145.62 *
# ram_clk$SB_IO_OUT_$glb_clk                           129.17 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '5',
 '--placer-heap-timingweight',
 '26']

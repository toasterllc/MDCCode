# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    130.28 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              119.43 
# ice_img_clk16mhz$SB_IO_IN                            124.60 
# img_dclk$SB_IO_IN_$glb_clk                           135.01 *
# ram_clk$SB_IO_OUT_$glb_clk                           126.98 *

['--placer-heap-alpha',
 '0.325',
 '--placer-heap-beta',
 '0.625',
 '--placer-heap-critexp',
 '2',
 '--placer-heap-timingweight',
 '31']

# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         165.23 
# ICEApp.readoutfifo_r_clk_$glb_clk                    134.57 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              124.81 
# ice_img_clk16mhz$SB_IO_IN                            114.59 
# img_dclk$SB_IO_IN_$glb_clk                           133.07 *
# ram_clk$SB_IO_OUT_$glb_clk                           128.52 *

['--placer-heap-alpha',
 '0.25',
 '--placer-heap-beta',
 '0.5750000000000001',
 '--placer-heap-critexp',
 '1',
 '--placer-heap-timingweight',
 '31']

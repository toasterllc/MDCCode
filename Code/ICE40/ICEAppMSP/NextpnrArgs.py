# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         165.23 
# ICEApp.readoutfifo_r_clk_$glb_clk                    137.49 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              117.91 
# ice_img_clk16mhz$SB_IO_IN                            124.70 
# img_dclk$SB_IO_IN_$glb_clk                           138.31 *
# ram_clk$SB_IO_OUT_$glb_clk                           128.80 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '3',
 '--placer-heap-timingweight',
 '11']

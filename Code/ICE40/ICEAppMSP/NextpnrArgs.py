# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    138.89 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              103.03 
# ice_img_clk16mhz$SB_IO_IN                            116.95 
# img_dclk$SB_IO_IN_$glb_clk                           133.39 *
# ram_clk$SB_IO_OUT_$glb_clk                           134.77 *

['--placer-heap-alpha',
 '0.25',
 '--placer-heap-beta',
 '0.525',
 '--placer-heap-critexp',
 '2',
 '--placer-heap-timingweight',
 '11']

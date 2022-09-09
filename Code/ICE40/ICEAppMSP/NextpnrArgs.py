# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    133.82 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              103.68 
# ice_img_clk16mhz$SB_IO_IN                            132.07 
# img_dclk$SB_IO_IN_$glb_clk                           146.22 
# ram_clk$SB_IO_OUT_$glb_clk                           127.55 *

['--placer-heap-alpha',
 '0.4',
 '--placer-heap-beta',
 '0.525',
 '--placer-heap-critexp',
 '5',
 '--placer-heap-timingweight',
 '11']

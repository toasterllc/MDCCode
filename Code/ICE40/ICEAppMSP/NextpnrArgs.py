# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         183.02 
# ICEApp.readoutfifo_r_clk_$glb_clk                    131.72 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                               97.52 
# ice_img_clk16mhz$SB_IO_IN                            127.94 
# img_dclk$SB_IO_IN_$glb_clk                           149.97 *
# ram_clk$SB_IO_OUT_$glb_clk                           125.75 *

['--placer-heap-alpha',
 '0.375',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '4',
 '--placer-heap-timingweight',
 '6']

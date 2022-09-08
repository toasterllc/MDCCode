# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         168.35 
# ICEApp.readoutfifo_r_clk_$glb_clk                    135.85 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              102.77 
# ice_img_clk16mhz$SB_IO_IN                            133.64 
# img_dclk$SB_IO_IN_$glb_clk                           146.37 *
# ram_clk$SB_IO_OUT_$glb_clk                           127.26 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '1',
 '--placer-heap-timingweight',
 '1']

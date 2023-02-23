# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         163.53 
# ICEApp.readoutfifo_r_clk_$glb_clk                    133.82 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                               95.20 
# ice_img_clk16mhz$SB_IO_IN                            119.59 
# img_dclk$SB_IO_IN_$glb_clk                           146.22 *
# ram_clk$SB_IO_OUT_$glb_clk                           128.47 *

['--placer-heap-alpha',
 '0.30000000000000004',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '4',
 '--placer-heap-timingweight',
 '11']

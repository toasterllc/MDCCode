# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         161.68 
# ICEApp.readoutfifo_r_clk_$glb_clk                    127.23 
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              116.24 
# ice_img_clk16mhz$SB_IO_IN                            126.25 
# img_dclk$SB_IO_IN_$glb_clk                           164.96 
# ram_clk$SB_IO_OUT_$glb_clk                           129.68 *

['--placer-heap-alpha',
 '0.375',
 '--placer-heap-beta',
 '0.5750000000000001',
 '--placer-heap-critexp',
 '5',
 '--placer-heap-timingweight',
 '31']

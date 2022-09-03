# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         170.94 
# ICEApp.readoutfifo_r_clk_$glb_clk                    135.98 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              108.59 
# ice_img_clk16mhz$SB_IO_IN                            127.62 
# img_dclk$SB_IO_IN_$glb_clk                           139.10 *
# ram_clk$SB_IO_OUT_$glb_clk                           123.98 *

['--placer-heap-alpha',
 '0.375',
 '--placer-heap-beta',
 '0.5750000000000001',
 '--placer-heap-critexp',
 '4',
 '--placer-heap-timingweight',
 '31']

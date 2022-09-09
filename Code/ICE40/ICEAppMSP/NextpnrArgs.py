# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         148.41 
# ICEApp.readoutfifo_r_clk_$glb_clk                    130.63 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              112.57 
# ice_img_clk16mhz$SB_IO_IN                            136.72 
# img_dclk$SB_IO_IN_$glb_clk                           145.10 
# ram_clk$SB_IO_OUT_$glb_clk                           127.03 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '1',
 '--placer-heap-timingweight',
 '16']

# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         191.86 
# ICEApp.readoutfifo_r_clk_$glb_clk                    132.77 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              110.52 
# ice_img_clk16mhz$SB_IO_IN                            125.71 
# img_dclk$SB_IO_IN_$glb_clk                           148.65 *
# ram_clk$SB_IO_OUT_$glb_clk                           126.65 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '1',
 '--placer-heap-timingweight',
 '16']

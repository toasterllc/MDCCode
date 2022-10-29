# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         196.35 
# ICEApp.readoutfifo_r_clk_$glb_clk                    136.24 *
# ICEApp.sd_clk_int                                    316.06 
# ICEApp.spi_clk_$glb_clk                              116.00 
# ice_img_clk16mhz$SB_IO_IN                            123.41 
# img_dclk$SB_IO_IN_$glb_clk                           145.62 *
# ram_clk$SB_IO_OUT_$glb_clk                           130.26 *

['--placer-heap-alpha',
 '0.275',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '1',
 '--placer-heap-timingweight',
 '26']

# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         199.60 
# ICEApp.readoutfifo_r_clk_$glb_clk                    135.21 *
# ICEApp.sd_clk_int                                    316.06 
# ICEApp.spi_clk_$glb_clk                               97.78 
# ice_img_clk16mhz$SB_IO_IN                            127.03 
# img_dclk$SB_IO_IN_$glb_clk                           145.62 *
# ram_clk$SB_IO_OUT_$glb_clk                           122.10 *

['--placer-heap-alpha',
 '0.30000000000000004',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '9',
 '--placer-heap-timingweight',
 '6']

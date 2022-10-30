# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         202.14 
# ICEApp.readoutfifo_r_clk_$glb_clk                    140.53 *
# ICEApp.sd_clk_int                                    316.06 
# ICEApp.spi_clk_$glb_clk                              118.46 
# ice_img_clk16mhz$SB_IO_IN                            135.21 
# img_dclk$SB_IO_IN_$glb_clk                           150.06 *
# ram_clk$SB_IO_OUT_$glb_clk                           126.87 *

['--placer-heap-alpha',
 '0.25',
 '--placer-heap-beta',
 '0.525',
 '--placer-heap-critexp',
 '4',
 '--placer-heap-timingweight',
 '16']

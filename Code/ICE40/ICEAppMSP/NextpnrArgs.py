# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    130.63 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              107.12 
# ice_img_clk16mhz$SB_IO_IN                            128.40 
# img_dclk$SB_IO_IN_$glb_clk                           141.02 *
# ram_clk$SB_IO_OUT_$glb_clk                           130.40 *

['--placer-heap-alpha',
 '0.30000000000000004',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '4',
 '--placer-heap-timingweight',
 '21']

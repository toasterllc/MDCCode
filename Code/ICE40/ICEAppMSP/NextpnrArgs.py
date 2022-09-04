# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    142.35 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              115.51 
# ice_img_clk16mhz$SB_IO_IN                            118.11 
# img_dclk$SB_IO_IN_$glb_clk                           136.05 *
# ram_clk$SB_IO_OUT_$glb_clk                           120.09 *

['--placer-heap-alpha',
 '0.375',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '3',
 '--placer-heap-timingweight',
 '31']

# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    133.56 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              117.38 
# ice_img_clk16mhz$SB_IO_IN                            131.37 
# img_dclk$SB_IO_IN_$glb_clk                           138.16 
# ram_clk$SB_IO_OUT_$glb_clk                           126.42 *

['--placer-heap-alpha',
 '0.375',
 '--placer-heap-beta',
 '0.5750000000000001',
 '--placer-heap-critexp',
 '6',
 '--placer-heap-timingweight',
 '26']

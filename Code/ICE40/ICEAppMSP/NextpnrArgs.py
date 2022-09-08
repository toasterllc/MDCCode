# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         166.78 
# ICEApp.readoutfifo_r_clk_$glb_clk                    137.93 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              106.38 
# ice_img_clk16mhz$SB_IO_IN                            121.01 
# img_dclk$SB_IO_IN_$glb_clk                           134.83 *
# ram_clk$SB_IO_OUT_$glb_clk                           126.42 *

['--placer-heap-alpha',
 '0.42500000000000004',
 '--placer-heap-beta',
 '0.5750000000000001',
 '--placer-heap-critexp',
 '1',
 '--placer-heap-timingweight',
 '16']

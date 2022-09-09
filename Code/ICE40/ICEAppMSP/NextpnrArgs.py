# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         170.94 
# ICEApp.readoutfifo_r_clk_$glb_clk                    133.07 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              116.43 
# ice_img_clk16mhz$SB_IO_IN                            121.42 
# img_dclk$SB_IO_IN_$glb_clk                           139.10 
# ram_clk$SB_IO_OUT_$glb_clk                           127.15 *

['--placer-heap-alpha',
 '0.07500000000000001',
 '--placer-heap-beta',
 '0.5750000000000001',
 '--placer-heap-critexp',
 '2',
 '--placer-heap-timingweight',
 '16']

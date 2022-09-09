# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         160.95 
# ICEApp.readoutfifo_r_clk_$glb_clk                    142.76 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                               91.84 
# ice_img_clk16mhz$SB_IO_IN                            126.14 
# img_dclk$SB_IO_IN_$glb_clk                           134.03 
# ram_clk$SB_IO_OUT_$glb_clk                           128.70 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '7',
 '--placer-heap-timingweight',
 '6']

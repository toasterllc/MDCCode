# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         199.60 
# ICEApp.readoutfifo_r_clk_$glb_clk                    138.89 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                               90.30 
# ice_img_clk16mhz$SB_IO_IN                            117.04 
# img_dclk$SB_IO_IN_$glb_clk                           138.16 *
# ram_clk$SB_IO_OUT_$glb_clk                           129.28 *

['--placer-heap-alpha',
 '0.30000000000000004',
 '--placer-heap-beta',
 '0.525',
 '--placer-heap-critexp',
 '10',
 '--placer-heap-timingweight',
 '11']

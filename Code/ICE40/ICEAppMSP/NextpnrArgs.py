# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         188.32 
# ICEApp.readoutfifo_r_clk_$glb_clk                    133.82 *
# ICEApp.sd_clk_int                                    316.06 
# ICEApp.spi_clk_$glb_clk                              106.33 
# ice_img_clk16mhz$SB_IO_IN                            133.07 
# img_dclk$SB_IO_IN_$glb_clk                           155.52 *
# ram_clk$SB_IO_OUT_$glb_clk                           128.63 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '6',
 '--placer-heap-timingweight',
 '21']

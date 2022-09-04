# * ICEAppMSP
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         176.03 
# ICEApp.readoutfifo_r_clk_$glb_clk                    142.35 *
# ICEApp.sd_clk_int                                    365.23 
# ICEApp.spi_clk_$glb_clk                              112.88 
# ice_img_clk16mhz$SB_IO_IN                            121.71 
# img_dclk$SB_IO_IN_$glb_clk                           141.04 *
# ram_clk$SB_IO_OUT_$glb_clk                           126.87 *

['--placer-heap-alpha',
 '0.375',
 '--placer-heap-beta',
 '0.65',
 '--placer-heap-critexp',
 '4',
 '--placer-heap-timingweight',
 '21']

# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    109.00 
# ice_img_clk16mhz$SB_IO_IN                            127.26 
# img_dclk$SB_IO_IN_$glb_clk                           129.22 
# ram_clk$SB_IO_OUT_$glb_clk                           131.18 *

['--placer-heap-alpha',
 '0.325',
 '--placer-heap-beta',
 '0.775',
 '--placer-heap-critexp',
 '1',
 '--placer-heap-timingweight',
 '31']

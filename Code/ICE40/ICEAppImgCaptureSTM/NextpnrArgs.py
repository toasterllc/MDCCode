# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                     96.99 
# ice_img_clk16mhz$SB_IO_IN                            126.14 
# img_dclk$SB_IO_IN_$glb_clk                           146.22 *
# ram_clk$SB_IO_OUT_$glb_clk                           127.08 *

['--placer-heap-alpha',
 '0.125',
 '--placer-heap-beta',
 '0.6000000000000001',
 '--placer-heap-critexp',
 '3',
 '--placer-heap-timingweight',
 '6']

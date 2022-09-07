# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    115.51 
# ice_img_clk16mhz$SB_IO_IN                            126.60 
# img_dclk$SB_IO_IN_$glb_clk                           161.13 *
# ram_clk$SB_IO_OUT_$glb_clk                           128.82 *

['--placer-heap-alpha',
 '0.1',
 '--placer-heap-beta',
 '0.9500000000000001',
 '--placer-heap-critexp',
 '6',
 '--placer-heap-timingweight',
 '26']

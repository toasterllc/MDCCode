# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    124.16 
# ice_img_clk16mhz$SB_IO_IN                            118.02 
# img_dclk$SB_IO_IN_$glb_clk                           146.37 *
# ram_clk$SB_IO_OUT_$glb_clk                           127.15 *

['--placer-heap-alpha',
 '0.2',
 '--placer-heap-beta',
 '0.65',
 '--placer-heap-critexp',
 '2',
 '--placer-heap-timingweight',
 '26']

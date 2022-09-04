# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    110.58 
# ice_img_clk16mhz$SB_IO_IN                            124.70 
# img_dclk$SB_IO_IN_$glb_clk                           164.96 *
# ram_clk$SB_IO_OUT_$glb_clk                           124.22 *

['--placer-heap-alpha',
 '0.2',
 '--placer-heap-beta',
 '0.55',
 '--placer-heap-critexp',
 '4',
 '--placer-heap-timingweight',
 '26']

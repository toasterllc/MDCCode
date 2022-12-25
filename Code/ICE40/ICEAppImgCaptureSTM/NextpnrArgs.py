# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    117.52 
# ice_img_clk16mhz$SB_IO_IN                            114.14 
# img_dclk$SB_IO_IN_$glb_clk                           145.62 *
# ram_clk$SB_IO_OUT_$glb_clk                           127.71 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '1',
 '--placer-heap-timingweight',
 '21']

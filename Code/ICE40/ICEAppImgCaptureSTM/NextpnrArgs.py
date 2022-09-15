# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    117.62 
# ice_img_clk16mhz$SB_IO_IN                            136.24 
# img_dclk$SB_IO_IN_$glb_clk                           140.06 *
# ram_clk$SB_IO_OUT_$glb_clk                           128.75 *

['--placer-heap-alpha',
 '0.30000000000000004',
 '--placer-heap-beta',
 '0.8500000000000001',
 '--placer-heap-critexp',
 '9',
 '--placer-heap-timingweight',
 '16']

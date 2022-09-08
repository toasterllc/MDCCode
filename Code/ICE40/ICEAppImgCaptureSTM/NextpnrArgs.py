# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    119.49 
# ice_img_clk16mhz$SB_IO_IN                            123.09 
# img_dclk$SB_IO_IN_$glb_clk                           138.75 
# ram_clk$SB_IO_OUT_$glb_clk                           128.47 *

['--placer-heap-alpha',
 '0.325',
 '--placer-heap-beta',
 '0.9',
 '--placer-heap-critexp',
 '2',
 '--placer-heap-timingweight',
 '21']

# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    109.67 
# ice_img_clk16mhz$SB_IO_IN_$glb_clk                   128.02 
# img_dclk$SB_IO_IN_$glb_clk                           134.01 *
# ram_clk$SB_IO_OUT_$glb_clk                           136.05 *

['--placer-heap-alpha',
 '0.125',
 '--placer-heap-beta',
 '0.875',
 '--placer-heap-critexp',
 '6',
 '--placer-heap-timingweight',
 '31']

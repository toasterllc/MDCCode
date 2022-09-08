# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    108.39 
# ice_img_clk16mhz$SB_IO_IN                            141.08 
# img_dclk$SB_IO_IN_$glb_clk                           130.60 
# ram_clk$SB_IO_OUT_$glb_clk                           131.67 *

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '5',
 '--placer-heap-timingweight',
 '11']

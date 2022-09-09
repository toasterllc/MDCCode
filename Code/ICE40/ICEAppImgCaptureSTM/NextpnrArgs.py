# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    104.53 
# ice_img_clk16mhz$SB_IO_IN                            121.54 
# img_dclk$SB_IO_IN_$glb_clk                           138.56 *
# ram_clk$SB_IO_OUT_$glb_clk                           130.58 *

['--placer-heap-alpha',
 '0.25',
 '--placer-heap-beta',
 '0.65',
 '--placer-heap-critexp',
 '7',
 '--placer-heap-timingweight',
 '31']

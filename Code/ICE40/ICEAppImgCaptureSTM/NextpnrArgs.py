# * ICEAppImgCaptureSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    132.45 
# ice_img_clk16mhz$SB_IO_IN                            122.68 
# img_dclk$SB_IO_IN_$glb_clk                           146.37 *
# ram_clk$SB_IO_OUT_$glb_clk                           130.87 *

['--placer-heap-alpha',
 '0.05',
 '--placer-heap-beta',
 '0.875',
 '--placer-heap-critexp',
 '8',
 '--placer-heap-timingweight',
 '31']

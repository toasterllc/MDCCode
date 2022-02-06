# * ICEAppImgCaptureSTM
# ----------------------------------------------------------
# Clk                                                   Freq
# ----------------------------------------------------------
# ICEApp.readoutfifo_r_clk_$glb_clk                    123.30
# ice_img_clk16mhz$SB_IO_IN_$glb_clk                   129.68
# img_dclk$SB_IO_IN_$glb_clk                           135.67
# ram_clk$SB_IO_OUT_$glb_clk                           133.64

['--placer-heap-alpha',
 '0.2',
 '--placer-heap-beta',
 '0.8',
 '--placer-heap-critexp',
 '8',
 '--placer-heap-timingweight',
 '21']
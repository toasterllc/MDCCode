# * ICEAppSDReadoutSTM
# -----------------------------------------------------------
# Clk                                                    Freq
# -----------------------------------------------------------
# ICEApp.SDController.clk_slow                         177.78 
# ICEApp.readoutfifo_prop_clk_$glb_clk                 136.31 *
# ICEApp.readoutfifo_r_clk_$glb_clk                    129.28 
# ICEApp.sd_clk_int                                    365.23 

['--placer-heap-alpha',
 '0.025',
 '--placer-heap-beta',
 '0.5',
 '--placer-heap-critexp',
 '5',
 '--placer-heap-timingweight',
 '16']

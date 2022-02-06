# ICEAppMSP
# 
# Clk                                                   Min      Max      Avg      Med
# --------------------------------------------------------------------------------------
# ICEApp.SDController.clk_slow                         177.78   177.78   177.78   177.78
# ICEApp.readoutfifo_r_clk_$glb_clk                    129.92   129.92   129.92   129.92
# ICEApp.sd_clk_int                                    365.23   365.23   365.23   365.23
# ICEApp.spi_clk_$glb_clk                              110.91   110.91   110.91   110.91
# ice_img_clk16mhz$SB_IO_IN                            123.41   123.41   123.41   123.41
# img_dclk$SB_IO_IN_$glb_clk                           135.67   135.67   135.67   135.67
# ram_clk$SB_IO_OUT_$glb_clk                           137.55   137.55   137.55   137.55

projNextpnrArgs=(
    --placer-heap-alpha         0.45
    --placer-heap-beta          0.775
    --placer-heap-critexp       1
    --placer-heap-timingweight  26
)

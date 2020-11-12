variable scriptDir [file dirname [file normalize [info script]]]

# begin:
    yosys read_verilog -I$scriptDir/Util -D ICE40_HX -lib -specify +/ice40/cells_sim.v Top.v
    yosys hierarchy -check -top Top
    yosys proc

# flatten:
    yosys flatten
    yosys tribuf -logic
    yosys deminout

# coarse:
    yosys opt_expr
    yosys opt_clean
    yosys check
    yosys opt
    yosys wreduce
    yosys peepopt
    yosys opt_clean
    yosys share
    yosys techmap -map +/cmp2lut.v -D LUT_WIDTH=4
    yosys opt_expr
    yosys opt_clean
    yosys memory_dff
    yosys wreduce {t:$mul}
    yosys alumacc
    yosys opt
    yosys fsm
    yosys opt -fast
    yosys memory -nomap
    yosys opt_clean

# map_bram:
    yosys memory_bram -rules +/ice40/brams.txt
    yosys techmap -map +/ice40/brams_map.v
    yosys ice40_braminit

# map_ffram:
    yosys opt -fast -mux_undef -undriven -fine
    yosys memory_map -iattr -attr !ram_block -attr !rom_block -attr logic_block -attr syn_ramstyle=auto -attr syn_ramstyle=registers -attr syn_romstyle=auto -attr syn_romstyle=logic
    yosys opt -undriven -fine

# map_gates:
    yosys ice40_wrapcarry
    yosys techmap -map +/techmap.v -map +/ice40/arith_map.v
    yosys opt -fast
    yosys ice40_opt

# map_ffs:
    yosys dff2dffe -direct-match {$_DFF_*}
    yosys dfflegalize -cell {$_DFF_?_} 0 -cell {$_DFFE_?P_} 0 -cell {$_DFF_?P?_} 0 -cell {$_DFFE_?P?P_} 0 -cell {$_SDFF_?P?_} 0 -cell {$_SDFFCE_?P?P_} 0 -cell {$_DLATCH_?_} x -mince -1
    yosys techmap -map +/ice40/ff_map.v
    yosys opt_expr -mux_undef
    yosys simplemap
    yosys ice40_ffssr
    yosys ice40_opt -full

# map_luts:
    yosys techmap -map +/ice40/latches_map.v
    yosys abc -dress -lut 4
    yosys ice40_wrapcarry -unwrap
    yosys techmap -map +/ice40/ff_map.v
    yosys clean
    yosys opt_lut -dlogic SB_CARRY:I0=2:I1=1:CI=0

# map_cells:
    yosys techmap -map +/ice40/cells_map.v
    yosys clean

# check:
    yosys autoname
    yosys hierarchy -check
    yosys stat
    yosys check -noinit

# json:
    yosys write_json Top.json

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -format Logic /test/sdram0/Clk
add wave -noupdate -format Logic /test/sdram0/Cke
add wave -noupdate -format Logic /test/sdram0/Sys_clk
add wave -noupdate -format Logic /test/sdram0/Cs_n
add wave -noupdate -format Logic /test/sdram0/Cas_n
add wave -noupdate -format Logic /test/sdram0/Ras_n
add wave -noupdate -format Logic /test/sdram0/We_n
add wave -noupdate -format Literal /test/sdram0/Dqm
add wave -noupdate -format Literal -radix unsigned /test/sdram0/Ba
add wave -noupdate -format Literal -radix decimal /test/sdram0/Addr
add wave -noupdate -format Literal -radix decimal /test/sdram0/Dq
add wave -noupdate -divider Command
add wave -noupdate -format Logic /test/sdram0/Read_enable
add wave -noupdate -format Logic /test/sdram0/Write_enable
add wave -noupdate -format Literal -radix decimal /test/sdram0/Mode_reg
add wave -noupdate -format Logic /test/sdram0/Data_in_enable
add wave -noupdate -format Logic /test/sdram0/Data_out_enable
add wave -noupdate -format Logic /test/sdram0/Aref_enable
add wave -noupdate -format Logic /test/sdram0/Active_enable
add wave -noupdate -format Logic /test/sdram0/Act_b0
add wave -noupdate -format Logic /test/sdram0/Act_b1
add wave -noupdate -format Logic /test/sdram0/Act_b2
add wave -noupdate -format Logic /test/sdram0/Act_b3
add wave -noupdate -format Logic /test/sdram0/Prech_enable
add wave -noupdate -format Logic /test/sdram0/Pc_b0
add wave -noupdate -format Logic /test/sdram0/Pc_b1
add wave -noupdate -format Logic /test/sdram0/Pc_b2
add wave -noupdate -format Logic /test/sdram0/Pc_b3
add wave -noupdate -format Logic /test/sdram0/Burst_term
add wave -noupdate -format Logic /test/sdram0/Mode_reg_enable
add wave -noupdate -format Literal -radix decimal /test/sdram0/Bank
add wave -noupdate -format Literal -radix decimal /test/sdram0/Row
add wave -noupdate -format Literal -radix decimal /test/sdram0/Col
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {514500 ps} {535500 ps}
WaveRestoreZoom {0 ps} {771750 ps}
configure wave -namecolwidth 195
configure wave -valuecolwidth 40
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

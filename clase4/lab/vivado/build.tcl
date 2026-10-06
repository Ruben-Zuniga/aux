# =============================================================================
# build.tcl — Síntesis + implementación para Arty A7-35T
# Jornada 4 — SoC 2-Core con Mailbox
#
# Top: soc_2core_top
# Uso: vivado -mode batch -source vivado/build.tcl
# =============================================================================

set PART    xc7a35ticsg324-1L
set TOP     soc_2core_top
set PROJ    soc_2core_build

create_project $PROJ vivado_work/$PROJ -part $PART -force

add_files rtl/picorv32.v
add_files [glob rtl/bram_sp.v rtl/bram_dp.v \
                rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
                rtl/soc_2core.v rtl/soc_2core_top.v]
add_files -fileset constrs_1 constraints/arty_a7.xdc

# Agregar hex de firmware para que Vivado los incluya en la síntesis
add_files fw0/main.hex
add_files fw1/main.hex

set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1

# Pre-copiar firmware al directorio de la run: $readmemh corre con
# cwd = .../synth_1/, donde las rutas relativas "fw0/main.hex"/"fw1/main.hex"
# no resuelven y Vivado lo ignora en silencio (deja las BRAM en cero).
set synth_dir [file join vivado_work $PROJ ${PROJ}.runs synth_1]
file mkdir [file join $synth_dir fw0]
file mkdir [file join $synth_dir fw1]
file copy -force fw0/main.hex [file join $synth_dir fw0 main.hex]
file copy -force fw1/main.hex [file join $synth_dir fw1 main.hex]

launch_runs synth_1
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

set bit_src [file join vivado_work $PROJ ${PROJ}.runs impl_1 ${TOP}.bit]
file copy -force $bit_src ${TOP}.bit

open_run impl_1
report_utilization   -file rpt_utilization.txt
report_timing_summary -file rpt_timing.txt
report_power         -file rpt_power.txt
close_design

puts "\n\[OK\] Bitstream: ${TOP}.bit\n"

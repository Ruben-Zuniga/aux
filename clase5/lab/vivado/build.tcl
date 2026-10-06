# =============================================================================
# build.tcl — Síntesis + implementación para Arty A7-35T
# Jornada 5 — Bootloader PRBS/BER
#
# Uso: vivado -mode batch -source vivado/build.tcl
#      (ejecutar desde el directorio lab/)
# =============================================================================

set PART    xc7a35ticsg324-1L
set TOP     soc_boot_top
set PROJ    soc_boot_build

create_project $PROJ vivado_work/$PROJ -part $PART -force

add_files rtl/picorv32.v
add_files [glob rtl/bram_sp.v \
                rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
                rtl/soc_boot.v rtl/soc_boot_top.v]

add_files -fileset constrs_1 constraints/arty_a7.xdc

set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1

# fw/boot.hex se referencia como ruta literal ("fw/boot.hex") dentro de
# soc_boot.v — synth_1 corre con cwd distinto a lab/, así que sin esta
# copia previa $readmemh no encuentra el archivo (falla en silencio: la
# BRAM queda en cero, sin error duro de síntesis).
set synth_dir [file join vivado_work $PROJ ${PROJ}.runs synth_1]
file mkdir [file join $synth_dir fw]
file copy -force fw/boot.hex [file join $synth_dir fw boot.hex]

launch_runs synth_1
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

set bit_src [file join vivado_work $PROJ ${PROJ}.runs impl_1 ${TOP}.bit]
file copy -force $bit_src ${TOP}.bit

open_run impl_1
report_utilization    -file rpt_utilization.txt
report_timing_summary -file rpt_timing.txt
report_power          -file rpt_power.txt
close_design

puts "\n\[OK\] Bitstream: ${TOP}.bit\n"

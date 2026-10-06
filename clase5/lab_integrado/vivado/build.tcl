# =============================================================================
# build.tcl — Síntesis + implementación para Arty A7-35T
# Jornada extra — mailbox (J4) + bootloader (J5)
#
# Uso: vivado -mode batch -source vivado/build.tcl
#      (ejecutar desde el directorio de este lab)
# =============================================================================

set PART    xc7a35ticsg324-1L
set TOP     soc_mboot_top
set PROJ    soc_mboot_build

create_project $PROJ vivado_work/$PROJ -part $PART -force

add_files rtl/picorv32.v
add_files [glob rtl/bram_sp.v rtl/bram_dp.v \
                rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
                rtl/soc_mboot.v rtl/soc_mboot_top.v]

add_files -fileset constrs_1 constraints/arty_a7.xdc

set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1

# fw0/main.hex se referencia como ruta relativa ("fw0/main.hex") dentro de
# soc_mboot.v (parámetro FW0_HEX, default de soc_mboot -- NO existe como
# parámetro de soc_mboot_top, así que un set_property generic sobre el
# fileset no llega a soc_mboot y Vivado lo ignora en silencio: "Unused top
# level parameter/generic FW0_HEX", $readmemh falla en silencio contra esa
# ruta relativa (synth_1 corre con cwd distinto a este directorio) y BRAM0
# queda en cero -- Core 0 arranca sin firmware y no imprime nada por UART.
# Mismo mecanismo que build.tcl de jornada 5 (lab/): copiar el .hex al
# directorio de synth_1 antes de lanzarla, para que la ruta relativa sí
# resuelva.
set synth_dir [file join vivado_work $PROJ ${PROJ}.runs synth_1]
file mkdir [file join $synth_dir fw0]
file copy -force fw0/main.hex [file join $synth_dir fw0 main.hex]

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

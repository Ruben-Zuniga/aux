# =============================================================================
# sim.tcl — Simulación XSIM del SoC Bootloader
# Jornada 5 — Bootloader PRBS/BER
#
# Uso: vivado -mode batch -source vivado/sim.tcl
#      (ejecutar desde el directorio lab/)
# =============================================================================

set PART    xc7a35ticsg324-1L
set SIM_TOP tb_soc_boot
set PROJ    sim_proj

create_project $PROJ vivado_work/$PROJ -part $PART -force

add_files rtl/picorv32.v
add_files [glob rtl/bram_sp.v \
                rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
                rtl/soc_boot.v]

add_files -fileset sim_1 sim/tb_soc_boot.v

set_property top     $SIM_TOP [get_filesets sim_1]
set_property top_lib {}       [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Pre-copiar firmwares al directorio de trabajo xsim
set xsim_dir [file normalize \
    [file join vivado_work $PROJ ${PROJ}.sim sim_1 behav xsim]]
file mkdir [file join $xsim_dir fw]
file copy -force fw/boot.hex [file join $xsim_dir fw boot.hex]
file copy -force fw/app.hex  [file join $xsim_dir fw app.hex]

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

puts "\n\[OK\] Simulación completa\n"

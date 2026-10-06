# =============================================================================
# sim.tcl — Simulación XSIM de soc_2core
# Jornada 4 — SoC 2-Core con Mailbox
#
# Uso: vivado -mode batch -source vivado/sim.tcl
#      (ejecutar desde el directorio lab/)
# =============================================================================

set PART    xc7a35ticsg324-1L
set SIM_TOP tb_soc_2core
set PROJ    sim_proj

create_project $PROJ vivado_work/$PROJ -part $PART -force

# RTL del proyecto
add_files rtl/picorv32.v
add_files [glob rtl/bram_sp.v rtl/bram_dp.v \
                rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
                rtl/soc_2core.v]

# Testbench
add_files -fileset sim_1 sim/tb_soc_2core.v

set_property top     $SIM_TOP [get_filesets sim_1]
set_property top_lib {}       [get_filesets sim_1]

# Define SIM: usa fw*/main_sim.hex y DELAY_CYCLES=200 (simulación rápida)
set_property verilog_define "SIM=1" [get_filesets sources_1]
set_property verilog_define "SIM=1" [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Pre-copiar firmwares: $readmemh se ejecuta al arrancar xsim (antes de run all)
set xsim_dir [file normalize \
    [file join vivado_work $PROJ ${PROJ}.sim sim_1 behav xsim]]
file mkdir [file join $xsim_dir fw0]
file mkdir [file join $xsim_dir fw1]
file copy -force fw0/main_sim.hex [file join $xsim_dir fw0 main_sim.hex]
file copy -force fw1/main_sim.hex [file join $xsim_dir fw1 main_sim.hex]

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

puts "\n\[OK\] Simulación completa\n"

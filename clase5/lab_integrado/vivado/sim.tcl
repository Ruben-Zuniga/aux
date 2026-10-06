# =============================================================================
# sim.tcl — Simulación XSIM del SoC mailbox + bootloader
# Jornada extra — mailbox (J4) + bootloader (J5)
#
# Uso: vivado -mode batch -source vivado/sim.tcl
#      (ejecutar desde el directorio de este lab, tras 'make hex')
# =============================================================================

set PART    xc7a35ticsg324-1L
set SIM_TOP tb_mboot
set PROJ    sim_proj

create_project $PROJ vivado_work/$PROJ -part $PART -force

add_files rtl/picorv32.v
add_files [glob rtl/bram_sp.v rtl/bram_dp.v \
                rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
                rtl/soc_mboot.v]

add_files -fileset sim_1 sim/tb_mboot.v

set_property top     $SIM_TOP [get_filesets sim_1]
set_property top_lib {}       [get_filesets sim_1]

# Generic FW0_HEX explícito: soc_mboot.v elige el default entre
# fw0/main.hex y fw0/main_sim.hex con `ifdef SIM, pero xsim no define ese
# macro -- sobreescribir el generic evita depender de eso.
set fw0_sim_abs [file normalize fw0/main_sim.hex]
set_property generic [list FW0_HEX=\"$fw0_sim_abs\"] [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Pre-copiar los .hex al directorio de trabajo xsim (mismo motivo que
# Jornada 5: $readmemh corre relativo al cwd de xsim, no al del lab)
set xsim_dir [file normalize \
    [file join vivado_work $PROJ ${PROJ}.sim sim_1 behav xsim]]
file mkdir [file join $xsim_dir fw0]
file mkdir [file join $xsim_dir fw1]
file copy -force fw0/main_sim.hex   [file join $xsim_dir fw0 main_sim.hex]
file copy -force fw1/worker.hex     [file join $xsim_dir fw1 worker.hex]
file copy -force fw1/worker_alt.hex [file join $xsim_dir fw1 worker_alt.hex]

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

puts "\n\[OK\] Simulación completa\n"

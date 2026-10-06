# =============================================================================
# open_gui.tcl — Abre proyecto en Vivado GUI
# Jornada 4 — SoC 2-Core con Mailbox
# =============================================================================

set PART    xc7a35ticsg324-1L
set SIM_TOP tb_soc_2core
set TOP     soc_2core_top
set PROJ    soc_2core_gui

create_project $PROJ vivado_work/$PROJ -part $PART -force

add_files rtl/picorv32.v
add_files [glob rtl/bram_sp.v rtl/bram_dp.v \
                rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
                rtl/soc_2core.v rtl/soc_2core_top.v]
add_files -fileset constrs_1 constraints/arty_a7.xdc
add_files -fileset sim_1     sim/tb_soc_2core.v

set_property top     $SIM_TOP [get_filesets sim_1]
set_property top_lib {}       [get_filesets sim_1]
set_property top     $TOP     [current_fileset]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Pre-copiar firmwares para xsim
set xsim_dir [file normalize \
    [file join vivado_work $PROJ ${PROJ}.sim sim_1 behav xsim]]
file mkdir [file join $xsim_dir fw0]
file mkdir [file join $xsim_dir fw1]
file copy -force fw0/main_sim.hex [file join $xsim_dir fw0 main_sim.hex]
file copy -force fw1/main_sim.hex [file join $xsim_dir fw1 main_sim.hex]

set_property -name {xsim.simulate.runtime} -value {10ms} \
    -objects [get_filesets sim_1]

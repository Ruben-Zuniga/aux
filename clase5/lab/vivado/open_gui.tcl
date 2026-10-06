# =============================================================================
# open_gui.tcl — Abre proyecto de síntesis en Vivado GUI
# Jornada 5 — Bootloader PRBS/BER
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

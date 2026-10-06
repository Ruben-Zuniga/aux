# =============================================================================
# open_gui.tcl — Abre proyecto de síntesis en Vivado GUI
# Jornada extra — mailbox (J4) + bootloader (J5)
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
add_files fw0/main.hex

set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1

set fw0_abs [file normalize fw0/main.hex]
set_property generic [list FW0_HEX=\"$fw0_abs\"] [current_fileset]

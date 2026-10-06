# =============================================================================
# program.tcl — Programar Arty A7-35T
# Jornada extra — mailbox (J4) + bootloader (J5)
# =============================================================================

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

set_property PROGRAM.FILE {soc_mboot_top.bit} $device
program_hw_devices $device

puts "\n\[OK\] Programación completada\n"

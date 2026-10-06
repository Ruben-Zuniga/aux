## =============================================================================
## arty_a7.xdc — Constraints para soc_2core_top en Arty A7-35T
## Jornada 4 — SoC 2-Core con Mailbox
## =============================================================================

## Reloj 100 MHz
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 10.00 [get_ports { clk }]

## Reset BTN0 (activo alto — invertido dentro del SoC)
set_property -dict { PACKAGE_PIN D9 IOSTANDARD LVCMOS33 } [get_ports { btn0 }]

## UART RX — Pmod JA1 (adaptador USB-TTL externo; FTDI onboard con micro-USB roto)
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { rx }]

## UART TX — Pmod JA2 (adaptador USB-TTL externo)
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { tx }]

## LEDs LD0–LD3
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

## Switches SW0–SW3 — nivel de inyección de error PRBS (Jornada 4)
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]

set_false_path -from [get_ports btn0]
set_false_path -from [get_ports rx]
set_false_path -from [get_ports {sw[*]}]
set_false_path -to   [get_ports tx]
set_false_path -to   [get_ports led]

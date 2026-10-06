# =============================================================================
# arty_a7.xdc — Constraints para soc_boot_top en Arty A7-35T
# Jornada 5 — Bootloader PRBS/BER
# =============================================================================

# Reloj principal: 100 MHz en E3
create_clock -period 10.000 -name clk [get_ports { clk100mhz }]
set_property PACKAGE_PIN E3 [get_ports { clk100mhz }]
set_property IOSTANDARD LVCMOS33 [get_ports { clk100mhz }]

# Reset: CPU_RESETN (activo bajo, pin C2)
set_property PACKAGE_PIN C2 [get_ports { ck_rst }]
set_property IOSTANDARD LVCMOS33 [get_ports { ck_rst }]

# UART por Pmod JA1/JA2 (el USB-UART onboard de esta placa está roto;
# NUNCA usar A9/D10)
set_property PACKAGE_PIN G13 [get_ports { uart_txd_in }]
set_property IOSTANDARD LVCMOS33 [get_ports { uart_txd_in }]
set_property PACKAGE_PIN B11 [get_ports { uart_rxd_out }]
set_property IOSTANDARD LVCMOS33 [get_ports { uart_rxd_out }]

# LEDs
set_property PACKAGE_PIN H5  [get_ports { led[0] }]
set_property IOSTANDARD LVCMOS33 [get_ports { led[0] }]
set_property PACKAGE_PIN J5  [get_ports { led[1] }]
set_property IOSTANDARD LVCMOS33 [get_ports { led[1] }]
set_property PACKAGE_PIN T9  [get_ports { led[2] }]
set_property IOSTANDARD LVCMOS33 [get_ports { led[2] }]
set_property PACKAGE_PIN T10 [get_ports { led[3] }]
set_property IOSTANDARD LVCMOS33 [get_ports { led[3] }]

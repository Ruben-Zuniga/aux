# =============================================================================
# Makefile — Jornada 5 (esqueleto): SoC PicoRV32 con Bootloader UART (recarga de PRBS/BER)
# Flujo A: iverilog/vvp  (simulación completa del boot)
# Flujo B: Vivado XSIM + síntesis para Arty A7-35T
# =============================================================================

PYTHON   = python3
VIVADO   = vivado
GTKWAVE  = gtkwave

CROSS ?= riscv-none-elf
CC       = $(CROSS)-gcc
OBJCOPY  = $(CROSS)-objcopy

BIN2HEX  = $(PYTHON) fw/bin2hex.py
START_S  = fw/start.S
LINK_LD  = fw/link.ld
PICORV32  = rtl/picorv32.v

CFLAGS   = -march=rv32im -mabi=ilp32 -nostdlib -ffreestanding \
           -O2 -Wall -T $(LINK_LD)
LDFLAGS  = -lgcc

TOP = soc_boot_top
BIT = $(TOP).bit

PORT ?= /dev/ttyUSB1
BAUD ?= 115200

# ─── Bootloader (Core 0) ─────────────────────────────────────────────────────
fw/boot.elf: fw/boot.c fw/uart.h $(START_S)
	$(CC) $(CFLAGS) $(START_S) fw/boot.c -o $@ $(LDFLAGS)

fw/boot.bin: fw/boot.elf
	$(OBJCOPY) -O binary $< $@

fw/boot.hex: fw/boot.bin
	$(BIN2HEX) $< > $@

# ─── Aplicación PRBS/BER (Core 1) — tasa de error por defecto ────────────────
fw/app.elf: fw/app_prbs.c fw/prbs.h $(START_S)
	$(CC) $(CFLAGS) $(START_S) fw/app_prbs.c -o $@ $(LDFLAGS)

fw/app.bin: fw/app.elf
	$(OBJCOPY) -O binary $< $@

fw/app.hex: fw/app.bin
	$(BIN2HEX) $< > $@

# ─── Variante con otra tasa de error, para la recarga en caliente ────────────
fw/app_alt.elf: fw/app_prbs.c fw/prbs.h $(START_S)
	$(CC) $(CFLAGS) -DERR_PERIOD_BITS=61u $(START_S) fw/app_prbs.c -o $@ $(LDFLAGS)

fw/app_alt.bin: fw/app_alt.elf
	$(OBJCOPY) -O binary $< $@

fw/app_alt.hex: fw/app_alt.bin
	$(BIN2HEX) $< > $@

hex: fw/boot.hex fw/app.hex fw/app_alt.hex

# ─── Simulación SoC completo (iverilog) ──────────────────────────────────────
SIM_SRCS = $(PICORV32) rtl/bram_sp.v \
           rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
           rtl/soc_boot.v sim/tb_soc_boot.v

sim.vvp: $(SIM_SRCS) fw/boot.hex fw/app.hex
	iverilog -g2005 -o $@ $(SIM_SRCS)

sim: sim.vvp
	vvp sim.vvp

wave: tb_soc_boot.vcd
	$(GTKWAVE) tb_soc_boot.vcd &

# ─── Cargar en el FPGA via loader.py ──────────────────────────────────────────
load: fw/app.bin
	$(PYTHON) host/loader.py --port $(PORT) --baud $(BAUD) --bin fw/app.bin --monitor

# Recargar en caliente con la variante de otra tasa de error (sin resintetizar)
load-alt: fw/app_alt.bin
	$(PYTHON) host/loader.py --port $(PORT) --baud $(BAUD) --bin fw/app_alt.bin --monitor

# ─── Simulación Vivado XSIM ──────────────────────────────────────────────────
xsim: hex
	mkdir -p vivado_work
	$(VIVADO) -mode batch -source vivado/sim.tcl \
	          -log vivado_work/sim.log \
	          -journal vivado_work/sim.jou

# ─── Síntesis + implementación ────────────────────────────────────────────────
synth: hex
	mkdir -p vivado_work
	$(VIVADO) -mode batch -source vivado/build.tcl \
	          -log vivado_work/build.log \
	          -journal vivado_work/build.jou

# ─── Vivado GUI ───────────────────────────────────────────────────────────────
gui: hex
	mkdir -p vivado_work
	$(VIVADO) -mode gui -source vivado/open_gui.tcl \
	          -log vivado_work/gui.log \
	          -journal vivado_work/gui.jou &

# ─── Programar Arty A7 ───────────────────────────────────────────────────────
program: $(BIT)
	$(VIVADO) -mode batch -source vivado/program.tcl \
	          -log vivado_work/program.log \
	          -journal vivado_work/program.jou

$(BIT):
	@echo "[ERROR] $(BIT) no encontrado — ejecutar 'make synth' primero"
	@exit 1

# ─── Flujo completo ──────────────────────────────────────────────────────────
all: hex sim

# ─── Herramientas ────────────────────────────────────────────────────────────
check:
	@echo "=== Verificando herramientas ==="
	@command -v iverilog >/dev/null 2>&1 && echo "[OK]    iverilog"  || echo "[FALTA] iverilog"
	@command -v $(VIVADO) >/dev/null 2>&1 && echo "[OK]    vivado"   || echo "[FALTA] vivado"
	@command -v $(CC)    >/dev/null 2>&1 && echo "[OK]    $(CC)"     || echo "[FALTA] $(CC)"

clean:
	rm -f fw/boot.elf fw/boot.bin fw/boot.hex
	rm -f fw/app.elf  fw/app.bin  fw/app.hex
	rm -f fw/app_alt.elf fw/app_alt.bin fw/app_alt.hex
	rm -f sim.vvp tb_soc_boot.vcd
	rm -f $(BIT) rpt_*.txt
	rm -rf vivado_work/ .Xil/ usage_statistics_webtalk.*

help:
	@echo ""
	@echo "  Jornada 5 — SoC PicoRV32 con Bootloader UART (PRBS/BER)"
	@echo ""
	@echo "  make check      Verificar herramientas"
	@echo "  make hex        Compilar bootloader + app PRBS (2 variantes)"
	@echo "  make sim        Simular boot completo con iverilog/vvp"
	@echo "  make wave       Abrir VCD en GTKWave"
	@echo "  make load       Cargar app.bin (tasa de error por defecto)"
	@echo "  make load-alt   Recargar en caliente app_alt.bin (otra tasa)"
	@echo "  make xsim       Simular con Vivado XSIM"
	@echo "  make synth      Sintetizar con Vivado (batch)"
	@echo "  make gui        Abrir proyecto en Vivado GUI"
	@echo "  make program    Programar la Arty A7"
	@echo "  make all        hex + sim"
	@echo "  make clean      Limpiar archivos generados"
	@echo ""

.PHONY: hex sim wave load load-alt xsim synth gui program all check clean help

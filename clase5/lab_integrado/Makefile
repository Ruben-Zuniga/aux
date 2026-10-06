# =============================================================================
# Makefile — Jornada extra: mailbox (J4) + bootloader (J5) en el mismo SoC
# =============================================================================

CROSS    ?= riscv-none-elf
CC        = $(CROSS)-gcc
OBJCOPY   = $(CROSS)-objcopy
OBJDUMP   = $(CROSS)-objdump
PYTHON    = python3

VIVADO    = vivado
GTKWAVE   = gtkwave
IVERILOG  = iverilog
VVP       = vvp

# JTAG de esta placa: FT232H genérico (el micro-USB de la Arty A7 está roto),
# Vivado hw_server no lo reconoce -> programar con openFPGALoader.
OPENFPGALOADER = openFPGALoader
CABLE          = ft232
BOARD          = arty_a7_35t

ARCH      = -march=rv32im_zicsr -mabi=ilp32
CFLAGS    = $(ARCH) -Os -ffreestanding -nostdlib

PICORV32  = rtl/picorv32.v
SIM_SRCS  = $(PICORV32) rtl/bram_sp.v rtl/bram_dp.v \
            rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
            rtl/soc_mboot.v sim/tb_mboot.v

TOP = soc_mboot_top
BIT = $(TOP).bit

PORT ?= /dev/ttyUSB1
BAUD ?= 115200

.PHONY: hex hex-sim disasm0 disasm1 sim wave synth gui program \
        load reload reload-alt xsim check clean help

# ─── Firmware Core 0: bootloader + manager de mailbox (hardware) ────────────
fw0/main.elf: fw0/start.S fw0/main.c fw0/link.ld fw0/uart.h fw0/mailbox_prbs.h fw0/prbs.h fw0/sw.h
	$(CC) $(CFLAGS) -nostdlib -T fw0/link.ld -o $@ fw0/start.S fw0/main.c

fw0/main.bin: fw0/main.elf
	$(OBJCOPY) -O binary $< $@

fw0/main.hex: fw0/main.bin
	$(PYTHON) fw0/bin2hex.py $< > $@
	@wc -l fw0/main.hex | awk '{print "[OK] fw0/main.hex: " $$1 " palabras"}'

# ─── Firmware Core 0 (simulación, DELAY corto) ───────────────────────────────
fw0/main_sim.elf: fw0/start.S fw0/main.c fw0/link.ld fw0/uart.h fw0/mailbox_prbs.h fw0/prbs.h fw0/sw.h
	$(CC) $(CFLAGS) -nostdlib -T fw0/link.ld -DSIM -o $@ fw0/start.S fw0/main.c

fw0/main_sim.bin: fw0/main_sim.elf
	$(OBJCOPY) -O binary $< $@

fw0/main_sim.hex: fw0/main_sim.bin
	$(PYTHON) fw0/bin2hex.py $< > $@
	@echo "[OK] fw0/main_sim.hex (DELAY_CYCLES=200)"

# ─── Firmware "de destino" de Core 1: checker de mailbox, cargado en runtime
# por el bootloader (nunca se embebe en la síntesis: BRAM1 nace vacía) ───────
fw1/worker.elf: fw1/start.S fw1/worker.c fw1/link.ld fw1/mailbox_prbs.h fw1/prbs.h
	$(CC) $(CFLAGS) -nostdlib -T fw1/link.ld -o $@ fw1/start.S fw1/worker.c

fw1/worker.bin: fw1/worker.elf
	$(OBJCOPY) -O binary $< $@

fw1/worker.hex: fw1/worker.bin
	$(PYTHON) fw0/bin2hex.py $< > $@

# Variante con otro polinomio de checker (ver fw1/worker_alt.c), para la
# demo de recarga en caliente: BER visiblemente distinto sin resintetizar.
fw1/worker_alt.elf: fw1/start.S fw1/worker_alt.c fw1/link.ld fw1/mailbox_prbs.h fw1/prbs.h
	$(CC) $(CFLAGS) -nostdlib -T fw1/link.ld -o $@ fw1/start.S fw1/worker_alt.c

fw1/worker_alt.bin: fw1/worker_alt.elf
	$(OBJCOPY) -O binary $< $@

fw1/worker_alt.hex: fw1/worker_alt.bin
	$(PYTHON) fw0/bin2hex.py $< > $@

hex: fw0/main.hex fw1/worker.bin fw1/worker_alt.bin
hex-sim: fw0/main_sim.hex fw1/worker.hex fw1/worker_alt.hex

# ─── Análisis ─────────────────────────────────────────────────────────────────
disasm0: fw0/main.elf
	$(OBJDUMP) -d -M no-aliases fw0/main.elf

disasm1: fw1/worker.elf
	$(OBJDUMP) -d -M no-aliases fw1/worker.elf

# ─── Simulación iverilog ──────────────────────────────────────────────────────
sim.vvp: $(SIM_SRCS) fw0/main_sim.hex fw1/worker.hex fw1/worker_alt.hex
	$(IVERILOG) -g2005 -DSIM -o $@ $(SIM_SRCS)

sim: sim.vvp
	$(VVP) $<

wave: tb_mboot.vcd
	$(GTKWAVE) tb_mboot.vcd &

# ─── Cargar/recargar Core 1 vía loader.py ────────────────────────────────────
# "load" y "reload" son el MISMO comando: el firmware de Core 0 atiende el
# handshake AA 55 igual la primera vez (Core 1 arranca vacío) que en
# cualquier vuelta posterior del loop de mailbox.
load: fw1/worker.bin
	$(PYTHON) host/loader.py --port $(PORT) --baud $(BAUD) --bin fw1/worker.bin --monitor

reload: fw1/worker.bin
	$(PYTHON) host/loader.py --port $(PORT) --baud $(BAUD) --bin fw1/worker.bin --monitor

reload-alt: fw1/worker_alt.bin
	$(PYTHON) host/loader.py --port $(PORT) --baud $(BAUD) --bin fw1/worker_alt.bin --monitor

# ─── Vivado ───────────────────────────────────────────────────────────────────
xsim: hex
	mkdir -p vivado_work
	$(VIVADO) -mode batch -source vivado/sim.tcl \
	          -log vivado_work/sim.log -journal vivado_work/sim.jou

synth: hex
	mkdir -p vivado_work
	$(VIVADO) -mode batch -source vivado/build.tcl \
	          -log vivado_work/build.log -journal vivado_work/build.jou

gui: hex hex-sim
	mkdir -p vivado_work
	$(VIVADO) -mode gui -source vivado/open_gui.tcl \
	          -log vivado_work/gui.log -journal vivado_work/gui.jou &

program: $(BIT)
	$(OPENFPGALOADER) -c $(CABLE) -b $(BOARD) $(BIT)

$(BIT):
	@echo "[ERROR] $(BIT) no encontrado — ejecutar 'make synth' primero"
	@exit 1

# ─── Utilidades ───────────────────────────────────────────────────────────────
check:
	@echo "=== Verificando herramientas ==="
	@command -v $(CC)       >/dev/null 2>&1 && echo "[OK]    $(CC)"    || echo "[FALTA] $(CC)"
	@command -v $(IVERILOG) >/dev/null 2>&1 && echo "[OK]    iverilog" || echo "[FALTA] iverilog"
	@command -v $(VIVADO)   >/dev/null 2>&1 && echo "[OK]    vivado"   || echo "[FALTA] vivado"
	@test -f $(PICORV32)    && echo "[OK]    picorv32.v" || echo "[FALTA] $(PICORV32)"

clean:
	rm -f fw0/main.elf fw0/main.bin fw0/main.hex
	rm -f fw0/main_sim.elf fw0/main_sim.bin fw0/main_sim.hex
	rm -f fw1/worker.elf fw1/worker.bin fw1/worker.hex
	rm -f fw1/worker_alt.elf fw1/worker_alt.bin fw1/worker_alt.hex
	rm -f sim.vvp tb_mboot.vcd
	rm -f $(BIT) rpt_*.txt
	rm -rf vivado_work/ .Xil/ usage_statistics_webtalk.*

help:
	@echo ""
	@echo "  Jornada extra — mailbox (J4) + bootloader (J5)"
	@echo ""
	@echo "  make check       Verificar herramientas"
	@echo "  make hex         Compilar Core 0 (fijo) + Core 1 (worker/worker_alt)"
	@echo "  make hex-sim     Compilar con -DSIM (Core 0, delay corto)"
	@echo "  make sim         Simular con iverilog (requiere: make hex-sim)"
	@echo "  make wave        Abrir VCD en GTKWave"
	@echo "  make load        Boot inicial: cargar fw1/worker.bin en Core 1"
	@echo "  make reload      Recarga en caliente con el mismo worker.bin"
	@echo "  make reload-alt  Recarga en caliente con worker_alt.bin (otro polinomio)"
	@echo "  make xsim        Simular con Vivado XSIM"
	@echo "  make synth       Sintetizar con Vivado (batch)"
	@echo "  make gui         Abrir proyecto en Vivado GUI"
	@echo "  make program     Programar la Arty A7"
	@echo "  make clean       Limpiar archivos generados"
	@echo ""

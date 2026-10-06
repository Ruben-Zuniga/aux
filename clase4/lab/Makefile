# =============================================================================
# Makefile — Jornada 4: SoC 2-Core + Mailbox
# =============================================================================

CROSS    ?= riscv-none-elf
CC        = $(CROSS)-gcc
OBJCOPY   = $(CROSS)-objcopy
OBJDUMP   = $(CROSS)-objdump
READELF   = $(CROSS)-readelf

VIVADO    = vivado
GTKWAVE   = gtkwave
IVERILOG  = iverilog
VVP       = vvp

ARCH      = -march=rv32im_zicsr -mabi=ilp32
FW_COMMON = common
CFLAGS    = $(ARCH) -Os -ffreestanding -nostdlib -I$(FW_COMMON)
LDFLAGS   = $(ARCH) -nostdlib -T fw0/link.ld

PICORV32  = rtl/picorv32.v
SIM_SRCS  = $(PICORV32) rtl/bram_sp.v rtl/bram_dp.v \
            rtl/uart_tx.v rtl/uart_rx.v rtl/uart_regs.v \
            rtl/soc_2core.v sim/tb_soc_2core.v

TOP = soc_2core_top
BIT = $(TOP).bit

.PHONY: hex hex-sim disasm0 disasm1 disasm0-src disasm1-src header0 header1 sections0 sections1 sim wave xsim synth gui program check clean help

# ─── Firmware Core 0 (hardware) ──────────────────────────────────────────────
fw0/main.elf: fw0/start.S fw0/main.c fw0/link.ld fw0/uart.h fw0/sw.h $(FW_COMMON)/mailbox_prbs.h $(FW_COMMON)/prbs.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ fw0/start.S fw0/main.c

fw0/main.bin: fw0/main.elf
	$(OBJCOPY) -O binary $< $@

fw0/main.hex: fw0/main.bin
	python3 fw0/bin2hex.py $< > $@
	@wc -l fw0/main.hex | awk '{print "[OK] fw0/main.hex: " $$1 " palabras"}'

# ─── Firmware Core 1 (hardware) ──────────────────────────────────────────────
fw1/main.elf: fw1/start.S fw1/worker.c fw1/link.ld $(FW_COMMON)/mailbox_prbs.h $(FW_COMMON)/prbs.h
	$(CC) $(CFLAGS) -T fw1/link.ld -o $@ fw1/start.S fw1/worker.c

fw1/main.bin: fw1/main.elf
	$(OBJCOPY) -O binary $< $@

fw1/main.hex: fw1/main.bin
	python3 fw1/bin2hex.py $< > $@
	@wc -l fw1/main.hex | awk '{print "[OK] fw1/main.hex: " $$1 " palabras"}'

hex: fw0/main.hex fw1/main.hex

# ─── Firmware (simulación, DELAY corto) ──────────────────────────────────────
fw0/main_sim.elf: fw0/start.S fw0/main.c fw0/link.ld fw0/uart.h fw0/sw.h $(FW_COMMON)/mailbox_prbs.h $(FW_COMMON)/prbs.h
	$(CC) $(CFLAGS) $(LDFLAGS) -DSIM -o $@ fw0/start.S fw0/main.c

fw0/main_sim.bin: fw0/main_sim.elf
	$(OBJCOPY) -O binary $< $@

fw0/main_sim.hex: fw0/main_sim.bin
	python3 fw0/bin2hex.py $< > $@
	@echo "[OK] fw0/main_sim.hex (DELAY_CYCLES=200)"

fw1/main_sim.elf: fw1/start.S fw1/worker.c fw1/link.ld $(FW_COMMON)/mailbox_prbs.h $(FW_COMMON)/prbs.h
	$(CC) $(CFLAGS) -T fw1/link.ld -DSIM -o $@ fw1/start.S fw1/worker.c

fw1/main_sim.bin: fw1/main_sim.elf
	$(OBJCOPY) -O binary $< $@

fw1/main_sim.hex: fw1/main_sim.bin
	python3 fw1/bin2hex.py $< > $@
	@echo "[OK] fw1/main_sim.hex"

hex-sim: fw0/main_sim.hex fw1/main_sim.hex

# ─── Análisis: desensamblado ─────────────────────────────────────────────────
disasm0: fw0/main.elf
	@echo ""
	@echo "=== Desensamblado de fw0/main.elf ==="
	@echo ""
	$(OBJDUMP) -d -M no-aliases fw0/main.elf

disasm1: fw1/main.elf
	@echo ""
	@echo "=== Desensamblado de fw1/main.elf ==="
	@echo ""
	$(OBJDUMP) -d -M no-aliases fw1/main.elf

# Interleave código C con el assembler generado (requiere -g en CFLAGS)
disasm0-src: CFLAGS += -g
disasm0-src: fw0/main.elf
	$(OBJDUMP) -d -S -M no-aliases fw0/main.elf

disasm1-src: CFLAGS += -g
disasm1-src: fw1/main.elf
	$(OBJDUMP) -d -S -M no-aliases fw1/main.elf

# Ver header del ELF (formato, entry point, tipo de máquina)
header0: fw0/main.elf
	@echo ""
	@echo "=== Header del ELF (Core 0) ==="
	$(READELF) -h fw0/main.elf

header1: fw1/main.elf
	@echo ""
	@echo "=== Header del ELF (Core 1) ==="
	$(READELF) -h fw1/main.elf

# Ver secciones y tamaños
sections0: fw0/main.elf
	@echo ""
	@echo "=== Secciones del ELF (Core 0) ==="
	$(READELF) -S fw0/main.elf
	@echo ""
	@echo "=== Mapa de memoria (Core 0) ==="
	$(CROSS)-nm --print-size --size-sort fw0/main.elf | tail -20

sections1: fw1/main.elf
	@echo ""
	@echo "=== Secciones del ELF (Core 1) ==="
	$(READELF) -S fw1/main.elf
	@echo ""
	@echo "=== Mapa de memoria (Core 1) ==="
	$(CROSS)-nm --print-size --size-sort fw1/main.elf | tail -20

# ─── Simulación iverilog ──────────────────────────────────────────────────────
sim.vvp: $(SIM_SRCS) fw0/main_sim.hex fw1/main_sim.hex
	$(IVERILOG) -g2005 -DSIM -o $@ $(SIM_SRCS)

sim: sim.vvp
	$(VVP) $<

wave: tb_soc_2core.vcd
	$(GTKWAVE) tb_soc_2core.vcd &

# ─── Vivado ───────────────────────────────────────────────────────────────────
xsim: hex hex-sim
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
	$(VIVADO) -mode batch -source vivado/program.tcl \
	          -log vivado_work/program.log -journal vivado_work/program.jou

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
	rm -f fw1/main.elf fw1/main.bin fw1/main.hex
	rm -f fw1/main_sim.elf fw1/main_sim.bin fw1/main_sim.hex
	rm -f sim.vvp tb_soc_2core.vcd
	rm -f $(BIT) rpt_*.txt
	rm -rf vivado_work/ .Xil/ usage_statistics_webtalk.*

help:
	@echo ""
	@echo "  Jornada 4 — SoC 2-Core + Mailbox"
	@echo ""
	@echo "  make check       Verificar herramientas"
	@echo "  make hex         Compilar ambos firmwares → fw0/main.hex fw1/main.hex"
	@echo "  make hex-sim     Compilar con -DSIM (delay corto)"
	@echo "  make disasm0     Desensamblado Core 0"
	@echo "  make disasm1     Desensamblado Core 1"
	@echo "  make disasm0-src Desensamblado Core 0 con código C intercalado"
	@echo "  make disasm1-src Desensamblado Core 1 con código C intercalado"
	@echo "  make header0     Ver header del ELF Core 0 (readelf -h)"
	@echo "  make header1     Ver header del ELF Core 1 (readelf -h)"
	@echo "  make sections0   Ver secciones y tamaños del ELF Core 0 (readelf -S)"
	@echo "  make sections1   Ver secciones y tamaños del ELF Core 1 (readelf -S)"
	@echo "  make sim         Simular con iverilog (requiere: make hex-sim)"
	@echo "  make wave        Abrir VCD en GTKWave"
	@echo "  make xsim        Simular con Vivado XSIM (batch)"
	@echo "  make synth       Sintetizar con Vivado (batch)"
	@echo "  make gui         Abrir proyecto en Vivado GUI"
	@echo "  make program     Programar la Arty A7"
	@echo "  make clean       Limpiar archivos generados"
	@echo ""

// =============================================================================
// soc_boot.v — SoC Bootloader Dual-Core PicoRV32
// Jornada 5 — Bootloader PRBS/BER — ESQUELETO PARA ESTUDIANTES
//
// Core 0: ejecuta bootloader desde BRAM0 (pre-cargado en síntesis)
//         puede escribir al BRAM1 de Core 1 vía ventana de boot (0x100000)
// Core 1: BRAM1 inicialmente vacía; cargada en runtime por el bootloader
//
// Mapa de memoria Core 0:
//   0x000000-0x003FFF  BRAM0  (bootloader, 16 KB)
//   0x100000-0x103FFF  Ventana de boot → BRAM1 de Core 1 (solo escritura)
//   0x300000-0x30FFFF  UART   (registros de datos y estado)
//   0x310000-0x31FFFF  SYSCTRL: bit[0]=liberar Core1, bits[7:4]=LED[3:0]
//
// Mapa de memoria Core 1:
//   0x000000-0x003FFF  BRAM1  (aplicación cargada por bootloader)
//   0x300000-0x30FFFF  GPIO   bits[3:0] = LED (OR con LED del SYSCTRL)
// =============================================================================

module soc_boot #(
    parameter MEM_WORDS = 4096,           // palabras por BRAM (16 KB)
    parameter BOOT_FILE = "fw/boot.hex",  // firmware pre-cargado en BRAM0
    parameter CLK_HZ    = 100_000_000,
    parameter BAUD      = 115_200
)(
    input  wire       clk,
    input  wire       resetn,
    output wire [3:0] led,
    input  wire       rx,
    output wire       tx
);

localparam ADDR_W = 12;   // 12 bits → 4096 palabras = 16 KB por BRAM

// ─── Bus Core 0 ──────────────────────────────────────────────────────────────
wire [31:0] c0_addr, c0_wdata, c0_rdata;
wire  [3:0] c0_wstrb;
wire        c0_valid, c0_ready;

picorv32 #(
    .ENABLE_MUL(1), .ENABLE_DIV(1), .ENABLE_IRQ(0),
    .ENABLE_COUNTERS(1),
    .PROGADDR_RESET(32'h0000_0000),
    .STACKADDR(MEM_WORDS * 4)
) core0 (
    .clk(clk), .resetn(resetn),
    .mem_valid(c0_valid), .mem_ready(c0_ready),
    .mem_addr(c0_addr),   .mem_wdata(c0_wdata),
    .mem_wstrb(c0_wstrb), .mem_rdata(c0_rdata)
);

// ─── Bus Core 1 ──────────────────────────────────────────────────────────────
wire [31:0] c1_addr, c1_wdata, c1_rdata;
wire  [3:0] c1_wstrb;
wire        c1_valid, c1_ready;

// Core 1 arranca en reset; Core 0 lo libera escribiendo SYSCTRL[0]=1
reg  c1_resetn_r;
wire c1_resetn = resetn && c1_resetn_r;

picorv32 #(
    .ENABLE_MUL(1), .ENABLE_DIV(1), .ENABLE_IRQ(0),
    .ENABLE_COUNTERS(1),
    .PROGADDR_RESET(32'h0000_0000),
    .STACKADDR(MEM_WORDS * 4)
) core1 (
    .clk(clk), .resetn(c1_resetn),
    .mem_valid(c1_valid), .mem_ready(c1_ready),
    .mem_addr(c1_addr),   .mem_wdata(c1_wdata),
    .mem_wstrb(c1_wstrb), .mem_rdata(c1_rdata)
);

// ─── Decodificación Core 0 (COMPLETO — estudiar este patrón) ─────────────────
// 0x000000-0x003FFF: BRAM0        (addr[31:14]==0)
// 0x100000-0x103FFF: Ventana boot (addr[31:20]==12'h001, addr[19:14]==0)
// 0x300000-0x30FFFF: UART         (addr[31:20]==12'h003, addr[16]==0)
// 0x310000-0x31FFFF: SYSCTRL      (addr[31:20]==12'h003, addr[16]==1)
wire c0_sel_bram    = c0_valid && (c0_addr[31:14] == 18'h0);
wire c0_sel_boot    = c0_valid && (c0_addr[31:20] == 12'h001) && (c0_addr[19:14] == 6'h0);
wire c0_sel_uart    = c0_valid && (c0_addr[31:20] == 12'h003) && !c0_addr[16];
wire c0_sel_sysctrl = c0_valid && (c0_addr[31:20] == 12'h003) &&  c0_addr[16];

// ─── Decodificación Core 1 (COMPLETO) ────────────────────────────────────────
// 0x000000-0x003FFF: BRAM1  (addr[31:14]==0)
// 0x300000-0x30FFFF: GPIO   (addr[31:20]==12'h003, addr[16]==0)
wire c1_sel_bram = c1_valid && (c1_addr[31:14] == 18'h0);
wire c1_sel_gpio = c1_valid && (c1_addr[31:20] == 12'h003) && !c1_addr[16];

// ─── BRAM0 (Core 0, bootloader) — COMPLETA ───────────────────────────────────
wire [31:0] c0_bram_rdata;

bram_sp #(.ADDR_W(ADDR_W), .INIT_FILE(BOOT_FILE)) u_bram0 (
    .clk(clk), .ena(c0_sel_bram), .wea(c0_wstrb),
    .addr(c0_addr[ADDR_W+1:2]), .din(c0_wdata), .dout(c0_bram_rdata)
);

// ─── TODO 1: BRAM1 (Core 1) con ventana de boot ──────────────────────────────
// BRAM1 es accedida por dos masters según el estado del sistema:
//   - Mientras c1_resetn_r == 0: Core 0 escribe vía ventana de boot (c0_sel_boot)
//   - Cuando  c1_resetn_r == 1: Core 1 accede normalmente (c1_sel_bram)
//
// Debes definir señales de mux para: ena, wea, addr, din
// y luego instanciar u_bram1 con INIT_FILE="" (vacía al inicio).
//
// Pistas:
//   wire bram1_ena  = c1_resetn_r ? c1_sel_bram : c0_sel_boot;
//   wire [3:0] bram1_wea  = ...  (similar)
//   wire [ADDR_W-1:0] bram1_addr = ...
//   wire [31:0] bram1_din  = ...
//   wire [31:0] bram1_dout;
//
// TODO: declarar las señales de mux e instanciar u_bram1 aquí
wire bram1_ena = (c1_resetn_r) ? c1_sel_bram : c0_sel_boot;
wire [3:0] bram1_wea = (c1_resetn_r) ? c1_wstrb : (c0_sel_boot) ? c0_wstrb : 4'b0;
wire [ADDR_W-1:0] bram1_addr = (c1_resetn_r) ? c1_addr[ADDR_W+1:2] : c0_addr[ADDR_W+1:2];
wire [31:0] bram1_din = (c1_resetn_r) ? c1_wdata : c0_wdata;
wire [31:0] bram1_dout;

bram_sp #(
    .ADDR_W(ADDR_W),
    .INIT_FILE("")
) u_bram1 (
    .clk(clk),
    .ena(bram1_ena),
    .wea(bram1_wea),
    .addr(bram1_addr),
    .din(bram1_din),
    .dout(bram1_dout)
);

// wire [31:0] bram1_dout = 32'h0;  // <- reemplazar con la salida de u_bram1

// ─── UART (Core 0) — COMPLETA ────────────────────────────────────────────────
wire [31:0] uart_rdata;
wire        uart_ready;

uart_regs #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
    .clk(clk), .resetn(resetn),
    .sel(c0_sel_uart), .reg_sel(c0_addr[2]),
    .wstrb(c0_wstrb), .wdata(c0_wdata),
    .rdata(uart_rdata), .ready(uart_ready),
    .rx(rx), .tx(tx)
);

// ─── SYSCTRL (Core 0) — COMPLETA ─────────────────────────────────────────────
// bit[0]: libera reset de Core 1
// bits[7:4]: LED[3:0] de Core 0
reg [7:0] sysctrl_r;

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        sysctrl_r   <= 8'h0;
        c1_resetn_r <= 1'b0;
    end else begin
        if (c0_sel_sysctrl && |c0_wstrb)
            sysctrl_r <= c0_wdata[7:0];
        c1_resetn_r <= sysctrl_r[0];
    end
end

// ─── GPIO (Core 1) — COMPLETA ────────────────────────────────────────────────
// bits[3:0]: LED[3:0] de Core 1 (OR con LED de SYSCTRL)
reg [3:0] c1_gpio_r;

always @(posedge clk or negedge resetn) begin
    if (!resetn) c1_gpio_r <= 4'h0;
    else if (c1_sel_gpio && |c1_wstrb)
        c1_gpio_r <= c1_wdata[3:0];
end

assign led = sysctrl_r[7:4] | c1_gpio_r;

// ─── TODO 2: mem_ready Core 0 ────────────────────────────────────────────────
// BRAM0 y la ventana de boot tienen 1 ciclo de latencia (registradas).
// UART y SYSCTRL son inmediatas (ready combinacional).
//
// Necesitas dos registros: c0_bram_rdy_r y c0_boot_rdy_r
// que se activan un ciclo después de que se selecciona la BRAM/boot
// y se desactivan cuando c0_ready ya está en 1 (para no generar pulsos extra).
//
// Pista:
//   c0_bram_rdy_r <= c0_sel_bram && !c0_ready;
//   c0_boot_rdy_r <= c0_sel_boot && !c0_ready;
//
// TODO: completar el always @(posedge clk ...) para c0_bram_rdy_r y c0_boot_rdy_r
reg c0_bram_rdy_r, c0_boot_rdy_r;

always @(posedge clk) begin
    c0_bram_rdy_r <= c0_sel_bram && !c0_ready;
    c0_boot_rdy_r <= c0_sel_boot && !c0_ready;
end

assign c0_ready = c0_bram_rdy_r || c0_boot_rdy_r || uart_ready || c0_sel_sysctrl;

// ─── TODO 3: mem_ready Core 1 ────────────────────────────────────────────────
// Igual que Core 0 pero solo para BRAM1 y GPIO.
// GPIO es inmediata (como SYSCTRL en Core 0).
//
// TODO: completar el always @(posedge clk ...) para c1_bram_rdy_r
reg c1_bram_rdy_r;

always @(posedge clk) begin
    c1_bram_rdy_r <= c1_sel_bram && !c1_ready;
end

assign c1_ready = c1_bram_rdy_r || c1_sel_gpio;

// ─── mem_rdata Core 0 (COMPLETA) ─────────────────────────────────────────────
assign c0_rdata = c0_sel_bram    ? c0_bram_rdata        :
                  c0_sel_uart    ? uart_rdata            :
                  c0_sel_sysctrl ? {24'h0, sysctrl_r}   : 32'h0;

// ─── mem_rdata Core 1 (COMPLETA) ─────────────────────────────────────────────
assign c1_rdata = c1_sel_bram ? bram1_dout : 32'h0;

endmodule

// =============================================================================
// soc_2core.v — SoC con dos núcleos PicoRV32 + mailbox compartido
// Jornada 4 — SoC 2-Core con Mailbox  [ESQUELETO PARA ESTUDIANTES]
//
// Mapa de memoria (perspectiva de cada núcleo):
//   0x000000 – 0x003FFF  BRAM privada (instrucciones + datos, 16 KB)
//   0x200000             GPIO_LEDS — bits [3:0] → LD0..LD3  (Core 0, W)
//   0x200004             GPIO_SW   — bits [3:0] ← SW0..SW3  (Core 0, R)
//   0x300000             UART DATA                      (Core 0 solamente)
//   0x300004             UART STATUS                    (Core 0 solamente)
//   0x500000 – 0x5000FF  Mailbox compartido (64 palabras, dual-port BRAM)
//
// Mailbox — layout de palabras (ver fw0/mailbox_prbs.h):
//   0x500000            MBX_STATE    0=IDLE / 1=WORK / 2=DONE
//   0x500004–0x500083   MBX_DATA[32] Core 0 escribe un bloque PRBS (32 palabras)
//   0x500084            MBX_ERRORS   Core 1 escribe bits erróneos del bloque
//
// TODO: completar las secciones marcadas con TODO
// =============================================================================

module soc_2core #(
    parameter MEM_WORDS = 4096,        // palabras por BRAM privada (16 KB)
    parameter CLK_HZ    = 100_000_000,
    parameter BAUD      = 115_200
)(
    input  wire       clk,
    input  wire       resetn,
    output wire [3:0] led,
    input  wire [3:0] sw,             // SW0..SW3 — nivel de inyección de error (Jornada 4)
    input  wire       rx,
    output wire       tx,
    output wire       trap            // trap de cualquier núcleo
);

// ---------------------------------------------------------------------------
// Bus del núcleo 0
// ---------------------------------------------------------------------------
wire [31:0] m0_addr, m0_wdata, m0_rdata;
wire  [3:0] m0_wstrb;
wire        m0_valid, m0_ready, trap0;

// ---------------------------------------------------------------------------
// Bus del núcleo 1
// ---------------------------------------------------------------------------
wire [31:0] m1_addr, m1_wdata, m1_rdata;
wire  [3:0] m1_wstrb;
wire        m1_valid, m1_ready, trap1;

assign trap = trap0 | trap1;

// ---------------------------------------------------------------------------
// Núcleo 0 — PicoRV32
// ---------------------------------------------------------------------------
picorv32 #(
    .ENABLE_MUL      (1),
    .ENABLE_DIV      (1),
    .ENABLE_IRQ      (0),
    .ENABLE_COUNTERS (1),
    .PROGADDR_RESET  (32'h0000_0000),
    .STACKADDR       (MEM_WORDS * 4)
) core0 (
    .clk       (clk),
    .resetn    (resetn),
    .mem_valid (m0_valid),
    .mem_ready (m0_ready),
    .mem_addr  (m0_addr),
    .mem_wdata (m0_wdata),
    .mem_rdata (m0_rdata),
    .mem_wstrb (m0_wstrb),
    .trap      (trap0)
);

// ---------------------------------------------------------------------------
// Núcleo 1 — PicoRV32
// ---------------------------------------------------------------------------
picorv32 #(
    .ENABLE_MUL      (1),
    .ENABLE_DIV      (1),
    .ENABLE_IRQ      (0),
    .ENABLE_COUNTERS (1),
    .PROGADDR_RESET  (32'h0000_0000),
    .STACKADDR       (MEM_WORDS * 4)
) core1 (
    .clk       (clk),
    .resetn    (resetn),
    .mem_valid (m1_valid),
    .mem_ready (m1_ready),
    .mem_addr  (m1_addr),
    .mem_wdata (m1_wdata),
    .mem_rdata (m1_rdata),
    .mem_wstrb (m1_wstrb),
    .trap      (trap1)
);

// ---------------------------------------------------------------------------
// Decodificación de dirección
// ---------------------------------------------------------------------------
localparam ADDR_W = $clog2(MEM_WORDS);   // 12
localparam MBX_AW = 6;                   // 64 palabras mailbox

// Core 0
wire m0_sel_bram = m0_valid && (m0_addr[31:14] == 18'h0);      // 0x000000–0x003FFF
wire m0_sel_gpio = m0_valid && (m0_addr[31:20] == 12'h002);    // 0x200000–0x2FFFFF
wire m0_sel_uart = m0_valid && (m0_addr[31:20] == 12'h003);    // 0x300000–0x3FFFFF

// ===========================================================================
// TODO A — Agregar m0_sel_mbx y m1_sel_mbx para el rango 0x500000–0x5FFFFF
//   Observar cómo está hecha m0_sel_uart arriba y replicar el patrón:
//     wire m0_sel_uart = m0_valid && (m0_addr[31:20] == 12'h003);
//   El mailbox ocupa 12'h005.
// ===========================================================================
wire m0_sel_mbx  = m0_valid && (m0_addr[31:20] == 12'h005);   // ← completar

// Core 1
wire m1_sel_bram = m1_valid && (m1_addr[31:14] == 18'h0);
wire m1_sel_mbx  = m1_valid && (m1_addr[31:20] == 12'h005);   // ← completar

// ---------------------------------------------------------------------------
// BRAM privada Core 0
// ---------------------------------------------------------------------------
wire [31:0] bram0_rdata;

bram_sp #(
    .DATA_W   (32),
    .ADDR_W   (ADDR_W),
`ifdef SIM
    .INIT_FILE("fw0/main_sim.hex")
`else
    .INIT_FILE("fw0/main.hex")
`endif
) u_bram0 (
    .clk  (clk),
    .ena  (m0_sel_bram),
    .wea  (m0_wstrb),
    .addr (m0_addr[ADDR_W+1:2]),
    .din  (m0_wdata),
    .dout (bram0_rdata)
);

// ---------------------------------------------------------------------------
// BRAM privada Core 1
// ---------------------------------------------------------------------------
wire [31:0] bram1_rdata;

bram_sp #(
    .DATA_W   (32),
    .ADDR_W   (ADDR_W),
`ifdef SIM
    .INIT_FILE("fw1/main_sim.hex")
`else
    .INIT_FILE("fw1/main.hex")
`endif
) u_bram1 (
    .clk  (clk),
    .ena  (m1_sel_bram),
    .wea  (m1_wstrb),
    .addr (m1_addr[ADDR_W+1:2]),
    .din  (m1_wdata),
    .dout (bram1_rdata)
);

// ---------------------------------------------------------------------------
// Mailbox — BRAM dual-port compartida
// ---------------------------------------------------------------------------
// ===========================================================================
// TODO B — Instanciar bram_dp para el mailbox compartido
//   Descomentar y completar los '???' en la instancia siguiente.
//   Puerto A (Core 0): ena=???,  wea=|???,  addra=m0_addr[MBX_AW+1:2],  douta=mbx_rdata0
//   Puerto B (Core 1): enb=???,  web=|???,  addrb=m1_addr[MBX_AW+1:2],  doutb=mbx_rdata1
// ===========================================================================
wire [31:0] mbx_rdata0;
wire [31:0] mbx_rdata1;

bram_dp #(
    .DATA_W(32), 
    .ADDR_W(MBX_AW)
) 
u_mbx (
    // Puerto A
    .clka  (clk),
    .ena   (m0_sel_mbx),
    .wea   (|m0_wstrb),
    .addra (m0_addr[MBX_AW+1:2]),
    .dina  (m0_wdata),
    .douta (mbx_rdata0),
    // Puerto B
    .clkb  (clk),
    .enb   (m1_sel_mbx),
    .web   (|m1_wstrb),
    .addrb (m1_addr[MBX_AW+1:2]),
    .dinb  (m1_wdata),
    .doutb (mbx_rdata1)
);
// assign mbx_rdata0 = 32'h0;   // ← ELIMINAR cuando descomentes la instancia
// assign mbx_rdata1 = 32'h0;   // ← ELIMINAR cuando descomentes la instancia

// ---------------------------------------------------------------------------
// GPIO — salida a LEDs (offset 0x0) y entrada de switches (offset 0x4)
// ---------------------------------------------------------------------------
wire m0_gpio_is_sw = m0_addr[2];   // 0x200000=LEDs(W) / 0x200004=SW(R)

reg [3:0] gpio_reg;

always @(posedge clk) begin
    if (!resetn)
        gpio_reg <= 4'b0;
    else if (m0_sel_gpio && !m0_gpio_is_sw && |m0_wstrb)
        gpio_reg <= m0_wdata[3:0];
end

assign led = gpio_reg;

// ---------------------------------------------------------------------------
// UART (Core 0)
// ---------------------------------------------------------------------------
wire [31:0] uart_rdata;
wire        uart_ready;

uart_regs #(
    .CLK_HZ (CLK_HZ),
    .BAUD   (BAUD)
) u_uart (
    .clk     (clk),
    .resetn  (resetn),
    .sel     (m0_sel_uart),
    .reg_sel (m0_addr[2]),
    .wstrb   (m0_wstrb),
    .wdata   (m0_wdata),
    .rdata   (uart_rdata),
    .ready   (uart_ready),
    .rx      (rx),
    .tx      (tx)
);

// ---------------------------------------------------------------------------
// mem_ready Core 0 — BRAM y mailbox tienen 1 ciclo de latencia
// ---------------------------------------------------------------------------
reg bram0_ready_r, mbx0_ready_r;

always @(posedge clk) bram0_ready_r <= m0_sel_bram && !m0_ready;

// ===========================================================================
// TODO C — Registrar m0_sel_mbx para generar mbx0_ready_r
//   Mismo patrón que bram0_ready_r:
//     always @(posedge clk) bram0_ready_r <= m0_sel_bram && !m0_ready;
//   Reemplazar el assign por un always con m0_sel_mbx:
// ===========================================================================
always @(posedge clk) 
    mbx0_ready_r  <= m0_sel_mbx && !m0_ready;  // ← completar

// ===========================================================================
// TODO D — Agregar mbx0_ready_r a m0_ready
//   Sin esto el CPU cuelga esperando ready al acceder al mailbox.
//   Actual:   bram0_ready_r || m0_sel_gpio || uart_ready
//   Objetivo: agregar || ???
// ===========================================================================
assign m0_ready = bram0_ready_r || m0_sel_gpio || uart_ready || mbx0_ready_r;

// ---------------------------------------------------------------------------
// mem_ready Core 1
// ---------------------------------------------------------------------------
reg bram1_ready_r, mbx1_ready_r;

always @(posedge clk) bram1_ready_r <= m1_sel_bram && !m1_ready;

// ===========================================================================
// TODO E — Mismo patrón que Core 0 pero para mbx1_ready_r y m1_ready
// ===========================================================================
always @(posedge clk)
    mbx1_ready_r  <= m1_sel_mbx && !m1_ready;  // ← completar
assign m1_ready = bram1_ready_r || mbx1_ready_r;

// ---------------------------------------------------------------------------
// Multiplexor mem_rdata
// ---------------------------------------------------------------------------
// ===========================================================================
// TODO F — Agregar mbx_rdata0 al mux de Core 0
//   Patrón: agregar un caso antes del 32'h0 final:
//     m0_sel_mbx ? mbx_rdata0 :
// ===========================================================================
assign m0_rdata = (m0_sel_bram) ? bram0_rdata :
                  (m0_sel_gpio) ? ((m0_gpio_is_sw) ? {28'b0, sw} : {28'b0, gpio_reg}) :
                  (m0_sel_uart) ? uart_rdata :
                  (m0_sel_mbx)  ? mbx_rdata0 : 32'h0;

// ===========================================================================
// TODO G — Agregar mbx_rdata1 al mux de Core 1
//   Patrón: m1_sel_mbx ? mbx_rdata1 :
// ===========================================================================
assign m1_rdata = m1_sel_bram ? bram1_rdata :
                  m1_sel_mbx  ? mbx_rdata1  : 32'h0;

endmodule

// =============================================================================
// soc_mboot_top.v — Wrapper de síntesis para Arty A7-35T
// Jornada extra — mailbox (J4) + bootloader (J5) en el mismo SoC
//
// BTN0 (D9) activo-alto -> resetn activo-bajo dentro del SoC.
//
// Power-on-reset: PicoRV32 necesita ver un flanco real de resetn (no solo el
// nivel estático que deja la configuración) para arrancar a pedir memoria.
// por_cnt arranca en 0 (vía GSR) y mantiene resetn bajo unos pocos ciclos
// después de cada configuración, sin depender de que alguien apriete BTN0.
// =============================================================================

module soc_mboot_top (
    input  wire       clk,      // 100 MHz (E3)
    input  wire       btn0,     // BTN0 reset activo-alto (D9)
    output wire [3:0] led,      // LD0-LD3
    input  wire [3:0] sw,       // SW0-SW3, nivel de inyección de error
    input  wire       rx,       // UART RX — Pmod JA1 (G13)
    output wire       tx        // UART TX — Pmod JA2 (B11)
);

reg [3:0] por_cnt = 4'h0;
wire      por_done = (por_cnt == 4'hF);
always @(posedge clk)
    if (!por_done) por_cnt <= por_cnt + 1;

wire resetn = por_done & ~btn0;

soc_mboot #(
    .MEM_WORDS (4096),
    .CLK_HZ    (100_000_000),
    .BAUD      (115_200)
) u_soc (
    .clk    (clk),
    .resetn (resetn),
    .led    (led),
    .sw     (sw),
    .rx     (rx),
    .tx     (tx)
);

endmodule

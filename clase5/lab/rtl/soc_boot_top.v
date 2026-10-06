// =============================================================================
// soc_boot_top.v — Wrapper para síntesis Vivado (Arty A7-35T)
// Jornada 5 — Bootloader PRBS/BER
//
// Power-on-reset: PicoRV32 necesita ver un flanco real de resetn (no solo el
// nivel estático que deja la configuración) para arrancar a pedir memoria.
// por_cnt arranca en 0 (vía GSR) y mantiene resetn bajo unos pocos ciclos
// después de cada configuración, sin depender de que alguien apriete el botón.
// =============================================================================

module soc_boot_top (
    input  wire        clk100mhz,
    input  wire        ck_rst,       // activo bajo (botón RESET)
    output wire [3:0]  led,
    input  wire        uart_txd_in,  // RX del FPGA (TX del host)
    output wire        uart_rxd_out  // TX del FPGA (RX del host)
);

wire clk = clk100mhz;

reg [3:0] por_cnt = 4'h0;   // valor inicial explícito: modela el GSR real
                            // de la FPGA también en simulación
wire      por_done = (por_cnt == 4'hF);
always @(posedge clk)
    if (!por_done) por_cnt <= por_cnt + 1;
wire resetn = por_done & ck_rst;

soc_boot #(
    .MEM_WORDS(4096),
    .BOOT_FILE("fw/boot.hex"),
    .CLK_HZ  (100_000_000),
    .BAUD    (115_200)
) u_soc (
    .clk    (clk),
    .resetn (resetn),
    .led    (led),
    .rx     (uart_txd_in),
    .tx     (uart_rxd_out)
);

endmodule

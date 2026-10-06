// =============================================================================
// soc_mboot.v — SoC 2-Core con Mailbox (Jornada 4) + Bootloader (Jornada 5)
// Jornada extra — mailbox que sobrevive a la recarga en caliente  [ESQUELETO]
//
// Ya resolviste el mailbox (Jornada 4, soc_2core.v) y el bootloader
// (Jornada 5, soc_boot.v) por separado. Acá no hay que rederivar ninguno de
// los dos: la ventana de boot + SYSCTRL vienen dados tal cual los dejaste en
// tu propio soc_boot.v. Tu tarea es PEGAR el mailbox de Jornada 4 a este bus
// -- las secciones marcadas con TODO son las únicas que faltan.
//
// Fusión sin cambios de comportamiento de ninguna de las dos piezas:
//   - El mailbox compartido (bram_dp, protocolo IDLE/WORK/DONE) es EL MISMO
//     RTL de soc_2core.v (Jornada 4), sin tocar.
//   - La ventana de boot sobre BRAM1 (mux entre Core 0 y Core 1 según
//     c1_resetn_r) es LA MISMA RTL de soc_boot.v (Jornada 5), sin tocar.
// Lo único nuevo acá es que ambos mecanismos conviven en el mismo bus: la
// ventana de boot se puede reusar más de una vez (c1_resetn_r es un simple
// registro, no un fusible de una sola vez), así que Core 0 puede volver a
// poner a Core 1 en reset y reescribir su BRAM en cualquier momento — ver
// fw0/main.c: do_load_core1() se llama tanto en el boot inicial como en
// cada recarga en caliente disparada por el mismo handshake AA 55 por UART.
//
// Mapa de memoria Core 0:
//   0x000000-0x003FFF  BRAM0     (firmware fijo: boot + manager de mailbox)
//   0x100000-0x103FFF  Ventana de boot -> BRAM1 de Core 1 (solo escritura,
//                      activa mientras c1_resetn_r==0; reusable)
//   0x200000           GPIO_LEDS (bits[3:0], W)      — contador de bloques
//   0x200004           GPIO_SW   (bits[3:0], R)      — tasa de inyección
//   0x300000-0x30FFFF  UART      (registros de datos y estado)
//   0x310000-0x31FFFF  SYSCTRL   bit[0]=libera/retiene Core1, bits[7:4]=LED
//   0x500000-0x5FFFFF  Mailbox compartido (64 palabras, dual-port BRAM)
//
// Mapa de memoria Core 1:
//   0x000000-0x003FFF  BRAM1     (aplicación cargada por el bootloader;
//                      worker.c no tiene UART ni GPIO — igual que Jornada 4)
//   0x500000-0x5FFFFF  Mailbox compartido
// =============================================================================

module soc_mboot #(
    parameter MEM_WORDS = 4096,           // palabras por BRAM privada (16 KB)
    parameter CLK_HZ    = 100_000_000,
`ifdef SIM
    parameter FW0_HEX   = "fw0/main_sim.hex",
`else
    parameter FW0_HEX   = "fw0/main.hex",
`endif
    parameter BAUD      = 115_200
)(
    input  wire       clk,
    input  wire       resetn,
    output wire [3:0] led,
    input  wire [3:0] sw,             // SW0..SW3 — nivel de inyección de error
    input  wire       rx,
    output wire       tx
);

localparam ADDR_W = 12;   // 12 bits -> 4096 palabras = 16 KB por BRAM
localparam MBX_AW = 6;    // 64 palabras mailbox

// ─── Bus Core 0 ────────────────────────────────────────────────────────────
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

// ─── Bus Core 1 ────────────────────────────────────────────────────────────
wire [31:0] c1_addr, c1_wdata, c1_rdata;
wire  [3:0] c1_wstrb;
wire        c1_valid, c1_ready;

// Core 1 arranca en reset; Core 0 lo libera/retiene escribiendo SYSCTRL[0].
// A diferencia de un fusible de una sola vez, esto se puede togglear tantas
// veces como se quiera: cada vez que vuelve a bajar, la ventana de boot
// vuelve a tomar control de BRAM1 para una recarga en caliente.
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

// ─── Decodificación Core 0 ───────────────────────────────────────────────────
wire c0_sel_bram    = c0_valid && (c0_addr[31:14] == 18'h0);
wire c0_sel_boot    = c0_valid && (c0_addr[31:20] == 12'h001) && (c0_addr[19:14] == 6'h0);
wire c0_sel_gpio    = c0_valid && (c0_addr[31:20] == 12'h002);
wire c0_sel_uart    = c0_valid && (c0_addr[31:20] == 12'h003) && !c0_addr[16];
wire c0_sel_sysctrl = c0_valid && (c0_addr[31:20] == 12'h003) &&  c0_addr[16];

// ===========================================================================
// TODO A — Agregar c0_sel_mbx y c1_sel_mbx para el rango 0x500000–0x5FFFFF
//   Mismo patrón que c0_sel_uart/c0_sel_sysctrl arriba, o que m0_sel_mbx de
//   tu soc_2core.v de Jornada 4. El mailbox ocupa 12'h005.
// ===========================================================================
wire c0_sel_mbx     = c0_valid && (c0_addr[31:20] == 12'h005);   // ← completar

// ─── Decodificación Core 1 ───────────────────────────────────────────────────
wire c1_sel_bram = c1_valid && (c1_addr[31:14] == 18'h0);
wire c1_sel_mbx  = c1_valid && (c1_addr[31:20] == 12'h005);      // ← completar (TODO A)

// ─── BRAM0 (Core 0, firmware fijo) ───────────────────────────────────────────
wire [31:0] c0_bram_rdata;

bram_sp #(.ADDR_W(ADDR_W), .INIT_FILE(FW0_HEX)) u_bram0 (
    .clk(clk), .ena(c0_sel_bram), .wea(c0_wstrb),
    .addr(c0_addr[ADDR_W+1:2]), .din(c0_wdata), .dout(c0_bram_rdata)
);

// ─── BRAM1 (Core 1) con ventana de boot reusable ─────────────────────────────
// Idéntico al mux de soc_boot.v: mientras Core 1 está en reset, Core 0
// escribe vía la ventana de boot; apenas sale de reset, toma control de su
// propia BRAM. Como c1_resetn_r no es de una sola vez, este mux se reusa en
// cada recarga en caliente sin agregar hardware nuevo.
wire       bram1_ena  = c1_resetn_r ? c1_sel_bram : c0_sel_boot;
wire [3:0] bram1_wea  = c1_resetn_r ? c1_wstrb    : (c0_sel_boot ? c0_wstrb : 4'b0);
wire [ADDR_W-1:0] bram1_addr = c1_resetn_r ? c1_addr[ADDR_W+1:2] : c0_addr[ADDR_W+1:2];
wire [31:0] bram1_din  = c1_resetn_r ? c1_wdata   : c0_wdata;
wire [31:0] bram1_dout;

bram_sp #(.ADDR_W(ADDR_W), .INIT_FILE("")) u_bram1 (
    .clk(clk), .ena(bram1_ena), .wea(bram1_wea),
    .addr(bram1_addr), .din(bram1_din), .dout(bram1_dout)
);

// ===========================================================================
// TODO B — Instanciar bram_dp para el mailbox compartido (idéntico al que ya
//   armaste en soc_2core.v de Jornada 4). Descomentar y completar los '???'.
//   Puerto A (Core 0): ena=c0_sel_mbx,  wea=|c0_wstrb,  douta=mbx_rdata0
//   Puerto B (Core 1): enb=c1_sel_mbx,  web=|c1_wstrb,  doutb=mbx_rdata1
// ===========================================================================
wire [31:0] mbx_rdata0;
wire [31:0] mbx_rdata1;

// bram_dp #(.DATA_W(32), .ADDR_W(MBX_AW)) u_mbx (
//     .clka  (clk), .ena  (???), .wea  (|???),
//     .addra (c0_addr[MBX_AW+1:2]), .dina (c0_wdata), .douta (???),

//     .clkb  (clk), .enb  (???), .web  (|???),
//     .addrb (c1_addr[MBX_AW+1:2]), .dinb (c1_wdata), .doutb (???)
// );

bram_dp #(
    .DATA_W(32), 
    .ADDR_W(MBX_AW)
) 
u_mbx (
    // Puerto A
    .clka  (clk),
    .ena   (c0_sel_mbx),
    .wea   (|c0_wstrb),
    .addra (c0_addr[MBX_AW+1:2]),
    .dina  (c0_wdata),
    .douta (mbx_rdata0),
    // Puerto B
    .clkb  (clk),
    .enb   (c1_sel_mbx),
    .web   (|c1_wstrb),
    .addrb (c1_addr[MBX_AW+1:2]),
    .dinb  (c1_wdata),
    .doutb (mbx_rdata1)
);
// assign mbx_rdata0 = 32'h0;   // ← ELIMINAR cuando descomentes la instancia
// assign mbx_rdata1 = 32'h0;   // ← ELIMINAR cuando descomentes la instancia

// ─── GPIO (Core 0) — LEDs de estado (offset 0x0) y switches (offset 0x4) ───
wire m0_gpio_is_sw = c0_addr[2];

reg [3:0] gpio_reg;

always @(posedge clk) begin
    if (!resetn)
        gpio_reg <= 4'b0;
    else if (c0_sel_gpio && !m0_gpio_is_sw && |c0_wstrb)
        gpio_reg <= c0_wdata[3:0];
end

// ─── UART (Core 0) ────────────────────────────────────────────────────────
wire [31:0] uart_rdata;
wire        uart_ready;

uart_regs #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
    .clk(clk), .resetn(resetn),
    .sel(c0_sel_uart), .reg_sel(c0_addr[2]),
    .wstrb(c0_wstrb), .wdata(c0_wdata),
    .rdata(uart_rdata), .ready(uart_ready),
    .rx(rx), .tx(tx)
);

// ─── SYSCTRL (Core 0) ─────────────────────────────────────────────────────
// bit[0]: libera/retiene Core 1 (togglear a 0 = pausa para recargar BRAM1)
// bits[7:4]: LED[3:0] de estado del bootloader/manager
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

assign led = sysctrl_r[7:4] | gpio_reg;

// ─── mem_ready Core 0 ─────────────────────────────────────────────────────
// BRAM0, ventana de boot y mailbox tienen 1 ciclo de latencia; GPIO, UART y
// SYSCTRL son inmediatos.
reg c0_bram_rdy_r, c0_boot_rdy_r, c0_mbx_rdy_r;

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        c0_bram_rdy_r <= 1'b0;
        c0_boot_rdy_r <= 1'b0;
        c0_mbx_rdy_r  <= 1'b0;
    end else begin
        c0_bram_rdy_r <= c0_sel_bram && !c0_ready;
        c0_boot_rdy_r <= c0_sel_boot && !c0_ready;
        // ===================================================================
        // TODO C — Registrar c0_sel_mbx para generar c0_mbx_rdy_r
        //   Mismo patrón que las dos líneas de arriba.
        // ===================================================================
        c0_mbx_rdy_r  <= c0_sel_mbx && !c0_ready;   // ← completar: ??? && !c0_ready
    end
end

// ===========================================================================
// TODO D — Agregar c0_mbx_rdy_r a c0_ready
//   Sin esto el CPU cuelga esperando ready al acceder al mailbox.
// ===========================================================================
assign c0_ready = c0_bram_rdy_r || c0_boot_rdy_r ||
                   c0_sel_gpio || uart_ready || c0_sel_sysctrl || c0_mbx_rdy_r;   // ← falta || c0_mbx_rdy_r

// ─── mem_ready Core 1 ─────────────────────────────────────────────────────
reg c1_bram_rdy_r, c1_mbx_rdy_r;

// ===========================================================================
// TODO E — Mismo patrón que Core 0 (TODO C y D) pero para c1_mbx_rdy_r y
//   c1_ready.
// ===========================================================================
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        c1_bram_rdy_r <= 1'b0;
        c1_mbx_rdy_r  <= 1'b0;
    end else begin
        c1_bram_rdy_r <= c1_sel_bram && !c1_ready;
        c1_mbx_rdy_r  <= c1_sel_mbx && !c1_ready;   // ← completar: ??? && !c1_ready
    end
end

assign c1_ready = c1_bram_rdy_r || c1_mbx_rdy_r;   // ← falta || c1_mbx_rdy_r

// ─── mem_rdata Core 0 ─────────────────────────────────────────────────────
// ===========================================================================
// TODO F — Agregar el caso c0_sel_mbx al mux de lectura de Core 0
//   Patrón: agregar un caso antes del 32'h0 final, ej. c0_sel_mbx ? mbx_rdata0 :
// ===========================================================================
assign c0_rdata = c0_sel_bram    ? c0_bram_rdata :
                  c0_sel_gpio    ? (m0_gpio_is_sw ? {28'b0, sw} : {28'b0, gpio_reg}) :
                  c0_sel_uart    ? uart_rdata :
                  c0_sel_sysctrl ? {24'h0, sysctrl_r} :
                  c0_sel_mbx     ? mbx_rdata0 : 32'h0;
                  // (ventana de boot es solo-escritura, como en soc_boot.v)

// ─── mem_rdata Core 1 ─────────────────────────────────────────────────────
// ===========================================================================
// TODO G — Agregar el caso c1_sel_mbx al mux de lectura de Core 1
//   Patrón: c1_sel_mbx ? mbx_rdata1 :
// ===========================================================================
assign c1_rdata = c1_sel_bram ? bram1_dout :
                  c1_sel_mbx  ? mbx_rdata1 : 32'h0;

endmodule

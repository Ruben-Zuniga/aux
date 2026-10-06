// =============================================================================
// uart_regs.v — Periférico UART mapeado en memoria
// Jornada 5 — UART (reutilizado de la Jornada 2)
//
// Registros (base 0x300000):
//   +0x00  DATA   W: byte a transmitir   R: último byte recibido
//   +0x04  STATUS bit0=TX_BUSY  bit1=RX_VALID  bit2=RX_OVERFLOW
//
// Leer DATA limpia automáticamente RX_VALID y RX_OVERFLOW.
// El firmware debe verificar TX_BUSY antes de escribir DATA.
// =============================================================================

module uart_regs #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 115_200
)(
    input  wire        clk,
    input  wire        resetn,
    // Interfaz MMIO con el SoC
    input  wire        sel,       // chip-select (del decodificador)
    input  wire        reg_sel,   // 0 = DATA, 1 = STATUS  (mem_addr[2])
    input  wire [3:0]  wstrb,     // byte-enables del bus
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,     // ready inmediato (sin latencia de pipeline)
    // Pines físicos
    input  wire        rx,
    output wire        tx
);

// ---------------------------------------------------------------------------
// TX
// ---------------------------------------------------------------------------
reg [7:0] tx_data_r;
reg       tx_wr;
wire      tx_busy;

uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
    .clk    (clk),
    .resetn (resetn),
    .data_i (tx_data_r),
    .wr_i   (tx_wr),
    .busy_o (tx_busy),
    .tx_o   (tx)
);

// ---------------------------------------------------------------------------
// RX
// ---------------------------------------------------------------------------
wire [7:0] rx_data;
wire       rx_valid;

uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
    .clk    (clk),
    .resetn (resetn),
    .rx_i   (rx),
    .data_o (rx_data),
    .valid_o(rx_valid)
);

// Latch del byte recibido + flags de estado
reg [7:0] rx_latch;
reg       rx_valid_r;
reg       rx_overflow;

wire cpu_reads_data = sel && (wstrb == 4'b0) && !reg_sel;

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        rx_latch    <= 8'h0;
        rx_valid_r  <= 1'b0;
        rx_overflow <= 1'b0;
    end else begin
        if (rx_valid) begin
            // Nuevo byte: actualizar latch, detectar overflow
            rx_latch   <= rx_data;
            rx_valid_r <= 1'b1;
            if (rx_valid_r && !cpu_reads_data)
                rx_overflow <= 1'b1;
        end else if (cpu_reads_data) begin
            // CPU leyó DATA: limpiar flags (solo si no llegó byte simultáneo)
            rx_valid_r  <= 1'b0;
            rx_overflow <= 1'b0;
        end
    end
end

// ---------------------------------------------------------------------------
// Escritura a DATA: despachar TX
// ---------------------------------------------------------------------------
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        tx_data_r <= 8'h0;
        tx_wr     <= 1'b0;
    end else begin
        tx_wr <= 1'b0;
        if (sel && |wstrb && !reg_sel)
            { tx_data_r, tx_wr } <= { wdata[7:0], 1'b1 };
    end
end

// ---------------------------------------------------------------------------
// Lectura (combinacional)
// ---------------------------------------------------------------------------
always @(*) begin
    if (!reg_sel)
        rdata = {24'h0, rx_latch};
    else
        rdata = {29'h0, rx_overflow, rx_valid_r, tx_busy};
end

// ready inmediato: UART no tiene latencia de pipeline (a diferencia de BRAM)
assign ready = sel;

endmodule

// =============================================================================
// uart_rx.v — Receptor UART
// Jornada 5 — UART (reutilizado de la Jornada 2)
// =============================================================================

module uart_rx #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 115200
)(
    input  wire       clk,
    input  wire       resetn,
    input  wire       rx_i,       // línea serie
    output reg  [7:0] data_o,     // byte recibido
    output reg        valid_o     // pulso de 1 ciclo: dato listo
);

localparam DIVIDER  = CLK_HZ / BAUD;
localparam HALF_DIV = DIVIDER / 2;

// Sincronizador doble (anti-metaestabilidad)
reg rx_s1, rx_s2, rx_prev;
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        rx_s1 <= 1'b1; rx_s2 <= 1'b1; rx_prev <= 1'b1;
    end else begin
        rx_s1   <= rx_i;
        rx_s2   <= rx_s1;
        rx_prev <= rx_s2;
    end
end

// Detección de flanco descendente (inicio de start bit)
wire start_edge = rx_prev & ~rx_s2;

localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;
reg [1:0] state;

reg [11:0] baud_cnt;
reg  [2:0] bit_cnt;
reg  [7:0] shift;

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        state    <= IDLE;
        baud_cnt <= 0;
        bit_cnt  <= 0;
        shift    <= 0;
        data_o   <= 0;
        valid_o  <= 0;
    end else begin
        valid_o <= 1'b0;  // default: no válido

        case (state)
        IDLE: begin
            if (start_edge) begin
                baud_cnt <= HALF_DIV - 1;
                state    <= START;
            end
        end

        START: begin
            if (baud_cnt == 0) begin
                if (!rx_s2) begin              // confirmar start bit real
                    baud_cnt <= DIVIDER - 1;
                    bit_cnt  <= 0;
                    state    <= DATA;
                end else begin
                    state <= IDLE;             // glitch, ignorar
                end
            end else begin
                baud_cnt <= baud_cnt - 1;
            end
        end

        DATA: begin
            if (baud_cnt == 0) begin
                baud_cnt <= DIVIDER - 1;
                shift    <= {rx_s2, shift[7:1]};   // LSB-first
                if (bit_cnt == 3'd7) begin
                    state <= STOP;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end else begin
                baud_cnt <= baud_cnt - 1;
            end
        end

        STOP: begin
            if (baud_cnt == 0) begin
                if (rx_s2) begin               // stop bit válido
                    data_o  <= shift;
                    valid_o <= 1'b1;
                end
                state <= IDLE;
            end else begin
                baud_cnt <= baud_cnt - 1;
            end
        end
        endcase
    end
end

endmodule

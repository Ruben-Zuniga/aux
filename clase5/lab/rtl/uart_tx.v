// =============================================================================
// uart_tx.v — Transmisor UART
// Jornada 5 — UART (reutilizado de la Jornada 2)
// =============================================================================

module uart_tx #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 115200
)(
    input  wire       clk,
    input  wire       resetn,     // active-low
    input  wire [7:0] data_i,     // byte a transmitir
    input  wire       wr_i,       // pulso: cargar y enviar data_i
    output reg        busy_o,     // '1' mientras transmite
    output reg        tx_o        // línea serie
);

localparam DIVIDER = CLK_HZ / BAUD;  // ciclos por bit

localparam IDLE = 1'b0, SEND = 1'b1;
reg state;

reg [10:0] baud_cnt;
reg  [3:0] bit_cnt;
reg  [9:0] shift;  // {stop, data[7:0], start}

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        state    <= IDLE;
        tx_o     <= 1'b1;
        busy_o   <= 1'b0;
        baud_cnt <= 0;
        bit_cnt  <= 0;
        shift    <= 0;
    end else begin
        case (state)
        IDLE: begin
            tx_o <= 1'b1;
            if (wr_i && !busy_o) begin
                shift    <= {1'b1, data_i, 1'b0};  // stop + data + start
                baud_cnt <= 0;
                bit_cnt  <= 0;
                busy_o   <= 1'b1;
                state    <= SEND;
            end
        end

        SEND: begin
            if (baud_cnt == DIVIDER - 1) begin
                baud_cnt <= 0;
                tx_o     <= shift[0];
                shift    <= {1'b1, shift[9:1]};
                if (bit_cnt == 4'd9) begin
                    state  <= IDLE;
                    busy_o <= 1'b0;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end else begin
                baud_cnt <= baud_cnt + 1;
            end
        end
        endcase
    end
end

endmodule

// =============================================================================
// tb_soc_boot.v — Testbench para SoC Bootloader Dual-Core
// Jornada 5 — Bootloader PRBS/BER
//
// Simula la carga de firmware via UART:
//   1. Core 0 imprime banner del bootloader y espera sincronización
//   2. El testbench envía AA 55, espera ACK
//   3. El testbench envía fw/app.hex usando el protocolo boot:
//      [4 bytes tamaño LE] [chunk0: 64B + XOR] [chunk1: ...] ...
//      (el chunk 1 se manda con XOR incorrecto en su primer intento, a
//       propósito, para verificar el NACK + reintento del mismo chunk)
//   4. Core 0 escribe la app en BRAM1 y libera Core 1
//   5. Core 1 arranca y enciende LED[2]
// =============================================================================
`timescale 1ns/1ps

module tb_soc_boot;

localparam CLK_HZ    = 100_000_000;
localparam SIM_BAUD  = 10_000_000;        // 10 ciclos/bit → simulación rápida
localparam BIT_CYC   = CLK_HZ / SIM_BAUD; // = 10
localparam TIMEOUT   = 500_000;           // ciclos máximos (~5ms simulado)

localparam CHUNK_WORDS = 16;   // 16 words = 64 bytes por chunk
localparam APP_WORDS   = 256;  // palabras máx de la app (1 KB)

reg clk, resetn;
reg rx_r;      // línea RX que el testbench "envía" al FPGA
wire tx;
wire [3:0] led;

initial clk  = 0;
initial rx_r = 1;   // idle alto
always #5 clk = ~clk;   // 100 MHz

soc_boot #(
    .MEM_WORDS(4096),
    .BOOT_FILE("fw/boot.hex"),
    .CLK_HZ  (CLK_HZ),
    .BAUD    (SIM_BAUD)
) dut (
    .clk    (clk),
    .resetn (resetn),
    .led    (led),
    .rx     (rx_r),
    .tx     (tx)
);

// ─── Tarea: enviar un byte vía UART (host → FPGA) ────────────────────────────
task uart_send_byte;
    input [7:0] data_i;
    integer bit_i;
    begin
        rx_r = 0;                           // start bit
        repeat(BIT_CYC) @(posedge clk);
        for (bit_i = 0; bit_i < 8; bit_i = bit_i+1) begin
            rx_r = data_i[bit_i];           // LSB primero
            repeat(BIT_CYC) @(posedge clk);
        end
        rx_r = 1;                           // stop bit
        repeat(BIT_CYC) @(posedge clk);
    end
endtask

// ─── Tarea: capturar un byte de TX (FPGA → host) ─────────────────────────────
task uart_capture_byte;
    output [7:0] data_o;
    integer bit_i;
    begin
        @(negedge tx);
        #(BIT_CYC * 5);
        if (!tx) begin
            repeat(BIT_CYC) @(posedge clk);
            for (bit_i = 0; bit_i < 8; bit_i = bit_i+1) begin
                data_o[bit_i] = tx;
                repeat(BIT_CYC) @(posedge clk);
            end
        end
    end
endtask

// ─── Captura UART TX → consola ────────────────────────────────────────────────
// También arma resp_received/last_resp para que send_firmware pueda esperar
// bloqueante a la respuesta (ACK/NACK) de cada byte de sincronización o chunk.
reg [7:0] rx_byte;
reg       resp_received;
reg [7:0] last_resp;
initial begin
    rx_byte       = 0;
    resp_received = 0;
    forever begin
        uart_capture_byte(rx_byte);
        if (rx_byte >= 8'h20 || rx_byte == 8'h0A || rx_byte == 8'h0D) begin
            $write("%c", rx_byte);
            $fflush;
        end else if (rx_byte == 8'h06) begin
            $display("[T=%0t] ACK (0x06)", $time);
            last_resp     = rx_byte;
            resp_received = 1;
        end else if (rx_byte == 8'h15) begin
            $display("[T=%0t] NACK (0x15)", $time);
            last_resp     = rx_byte;
            resp_received = 1;
        end
    end
end

// ─── Memoria de la app ────────────────────────────────────────────────────────
reg [31:0] app_mem [0:APP_WORDS-1];
reg [31:0] app_nwords;

// Variables de módulo para las tareas de boot (Verilog-2001: no hay décl. locales en initial)
integer    fw_c, fw_w, fw_b, fw_i, fw_attempt;
reg [7:0]  fw_xor;
reg [31:0] fw_word;
reg [31:0] fw_total_bytes, fw_n_chunks;

// ─── Tarea: enviar firmware completo con protocolo boot ───────────────────────
// Incluye la sincronización AA 55 -> ACK, y corrompe a propósito el XOR del
// chunk 1 en su primer intento para verificar el mecanismo de NACK/reintento.
task send_firmware;
    begin
        fw_total_bytes = app_nwords * 4;
        fw_n_chunks    = app_nwords / CHUNK_WORDS;

        $display("[tb] Enviando %0d bytes (%0d chunks de 64)", fw_total_bytes, fw_n_chunks);

        // Sincronización: AA 55 -> ACK
        resp_received = 0;
        uart_send_byte(8'hAA);
        uart_send_byte(8'h55);
        $display("[T=%0t] [tb] Sync AA 55 enviado, esperando ACK...", $time);
        wait (resp_received == 1);
        $display("[T=%0t] [tb] ACK de sync recibido", $time);

        // Tamaño (4 bytes little-endian)
        uart_send_byte(fw_total_bytes[7:0]);
        uart_send_byte(fw_total_bytes[15:8]);
        uart_send_byte(fw_total_bytes[23:16]);
        uart_send_byte(fw_total_bytes[31:24]);
        $display("[T=%0t] [tb] Size enviado: %0d bytes", $time, fw_total_bytes);

        for (fw_c = 0; fw_c < fw_n_chunks; fw_c = fw_c+1) begin
            for (fw_attempt = 0; fw_attempt < 2; fw_attempt = fw_attempt+1) begin
                fw_xor = 0;

                // Enviar 16 words (64 bytes)
                for (fw_w = 0; fw_w < CHUNK_WORDS; fw_w = fw_w+1) begin
                    fw_word = app_mem[fw_c * CHUNK_WORDS + fw_w];
                    for (fw_b = 0; fw_b < 4; fw_b = fw_b+1) begin
                        uart_send_byte(fw_word[7:0]);
                        fw_xor = fw_xor ^ fw_word[7:0];
                        fw_word = fw_word >> 8;
                    end
                end

                resp_received = 0;
                if (fw_c == 1 && fw_attempt == 0) begin
                    // Chunk 1, primer intento: mandar XOR incorrecto a propósito
                    $display("[T=%0t] [tb] Chunk %0d: XOR incorrecto a proposito (test NACK/retry)", $time, fw_c);
                    uart_send_byte(fw_xor ^ 8'hFF);
                end else begin
                    $display("[T=%0t] [tb] Chunk %0d enviado, XOR=0x%02h", $time, fw_c, fw_xor);
                    uart_send_byte(fw_xor);
                end

                wait (resp_received == 1);
                if (last_resp == 8'h06) begin
                    fw_attempt = 2;   // ACK: cortar el loop de reintento
                end else begin
                    $display("[T=%0t] [tb] Chunk %0d: NACK, reintentando", $time, fw_c);
                end
            end
        end
    end
endtask

// ─── Hilo de carga de firmware ────────────────────────────────────────────────
initial begin
    // Cargar app.hex
    for (fw_i = 0; fw_i < APP_WORDS; fw_i = fw_i+1)
        app_mem[fw_i] = 32'h0;
    $readmemh("fw/app.hex", app_mem);

    // Calcular tamaño real: último word no-cero, redondeado a chunk (16 words)
    app_nwords = CHUNK_WORDS;  // mínimo 1 chunk
    for (fw_i = APP_WORDS-1; fw_i >= 0; fw_i = fw_i-1) begin
        if (app_mem[fw_i] != 32'h0 && app_nwords == CHUNK_WORDS) begin
            app_nwords = ((fw_i / CHUNK_WORDS) + 1) * CHUNK_WORDS;
        end
    end

    // Esperar a que Core 0 imprima su banner y quede bloqueado en wait_sync()
    repeat(12000) @(posedge clk);

    // Enviar firmware usando el protocolo de boot
    send_firmware;

    $display("[tb] Firmware enviado. Esperando Core 1...");
end


// ─── Reset y timeout ─────────────────────────────────────────────────────────
initial begin
`define DUMP_VCD
`ifdef DUMP_VCD
    $dumpfile("tb_soc_boot.vcd");
    $dumpvars(1, tb_soc_boot);
`endif
    resetn = 0;
    repeat(10) @(posedge clk);
    resetn = 1;

    repeat(TIMEOUT) @(posedge clk);
    $display("\n[tb] timeout (%0d ciclos)", TIMEOUT);
    $finish;
end

// ─── Monitor de LEDs ─────────────────────────────────────────────────────────
initial begin
    @(posedge resetn);
    forever begin
        @(led);
        $display("[T=%0t] LED = %04b", $time, led);
        if (led[2]) begin
            $display("[tb] Core 1 activo (LED[2]=1) — boot exitoso!");
            repeat(2000) @(posedge clk);
            $display("[tb] Simulacion completada.");
            $finish;
        end
    end
end

endmodule

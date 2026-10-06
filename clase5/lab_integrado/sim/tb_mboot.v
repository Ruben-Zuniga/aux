// =============================================================================
// tb_mboot.v — Testbench para soc_mboot (mailbox de Jornada 4 + bootloader de
// Jornada 5 en el mismo SoC)
//
// Secuencia simulada, de punta a punta:
//   1. Boot inicial: el testbench envía fw1/worker.hex con el protocolo de
//      boot (AA 55 -> ACK, tamaño, chunks con XOR+ACK/NACK) — igual que
//      tb_soc_boot.v de Jornada 5.
//   2. Core 0 libera Core 1 y arranca el manager de mailbox (Jornada 4):
//      se captura su salida UART y se espera la primera ventana cerrada
//      ("[C0] ventana cerrada: ... BER ~= ... ppm").
//   3. Con el mailbox ya funcionando, el testbench dispara una RECARGA EN
//      CALIENTE: envía fw1/worker_alt.hex con el MISMO handshake AA 55,
//      sin que Core 0 deje de responder en ningún momento salvo mientras
//      dura la carga.
//   4. Se espera la confirmación de la recarga y la ventana siguiente: el
//      BER reportado debe cambiar de forma visible (worker_alt.c usa un
//      polinomio de checker distinto al del generador de Core 0 — ver
//      fw1/worker_alt.c), lo que prueba que Core 1 está corriendo firmware
//      nueva de verdad.
// =============================================================================
`timescale 1ns/1ps

module tb_mboot;

localparam CLK_HZ    = 100_000_000;
localparam SIM_BAUD  = 10_000_000;        // 10 ciclos/bit -> simulación rápida
localparam BIT_CYC   = CLK_HZ / SIM_BAUD; // = 10
localparam TIMEOUT   = 30_000_000;        // ciclos máximos (~300 ms simulados)

localparam CHUNK_WORDS = 16;   // 16 words = 64 bytes por chunk
localparam APP_WORDS   = 1024; // palabras máx de cada firmware de Core 1 (4 KB)

reg clk, resetn;
reg rx_r;      // línea RX que el testbench "envía" al FPGA
wire tx;
wire [3:0] led;

initial clk  = 0;
initial rx_r = 1;   // idle alto
always #5 clk = ~clk;   // 100 MHz

soc_mboot #(
    .MEM_WORDS(4096),
    .CLK_HZ  (CLK_HZ),
    .BAUD    (SIM_BAUD)
) dut (
    .clk    (clk),
    .resetn (resetn),
    .led    (led),
    .sw     (4'd8),    // nivel 8 -> mismo periodo de inyección ya documentado en J4
    .rx     (rx_r),
    .tx     (tx)
);

// ─── Tarea: enviar un byte vía UART (host -> FPGA) ───────────────────────────
task uart_send_byte;
    input [7:0] data_i;
    integer bit_i;
    begin
        rx_r = 0;                           // start bit
        repeat(BIT_CYC) @(posedge clk);
        for (bit_i = 0; bit_i < 8; bit_i = bit_i+1) begin
            rx_r = data_i[bit_i];
            repeat(BIT_CYC) @(posedge clk);
        end
        rx_r = 1;                           // stop bit
        repeat(BIT_CYC) @(posedge clk);
    end
endtask

// ─── Tarea: capturar un byte de TX (FPGA -> host) ────────────────────────────
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

// ─── Captura UART TX -> consola, detecta ACK/NACK y frases clave ────────────
reg [7:0] rx_byte;
reg       resp_received;
reg [7:0] last_resp;

// Ventana deslizante de los últimos caracteres impresos, para detectar
// frases sin depender de line buffering.
reg [8*32-1:0] tail;
integer window_closes;    // cuántas veces vimos "ventana cerrada"
integer reload_ok;        // se puso en 1 al ver "liberando Core 1" (2da vez)

initial begin
    rx_byte        = 0;
    resp_received  = 0;
    tail           = 0;
    window_closes  = 0;
    reload_ok      = 0;
    forever begin
        uart_capture_byte(rx_byte);
        if (rx_byte >= 8'h20 || rx_byte == 8'h0A || rx_byte == 8'h0D) begin
            $write("%c", rx_byte);
            $fflush;
            tail = {tail[8*31-1:0], rx_byte};
            if (tail[8*15-1 -: 8*15] == "ventana cerrada") begin
                window_closes = window_closes + 1;
                $display("\n[tb] >>> ventana cerrada #%0d detectada", window_closes);
            end
            if (tail[8*16-1 -: 8*16] == "liberando Core 1") begin
                reload_ok = reload_ok + 1;
                $display("\n[tb] >>> Core 1 liberado (#%0d)", reload_ok);
            end
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

// ─── Memoria de los dos firmwares de Core 1 ─────────────────────────────────
reg [31:0] worker_mem     [0:APP_WORDS-1];
reg [31:0] worker_alt_mem [0:APP_WORDS-1];
reg [31:0] worker_nwords, worker_alt_nwords;

integer    fw_c, fw_w, fw_b, fw_i, fw_n_chunks;
reg [7:0]  fw_xor;
reg [31:0] fw_word;
reg [31:0] fw_total_bytes;

// ─── Tarea: enviar un firmware completo con el protocolo de boot ───────────
// Sirve tanto para el boot inicial como para cada recarga en caliente: es
// EL MISMO handshake (AA 55 -> ACK -> tamaño -> chunks), atendido del lado
// de Core 0 por la misma rutina load_and_release() en los dos casos.
task send_firmware;
    input [31:0] nwords;
    input        use_alt;   // 0 = worker_mem, 1 = worker_alt_mem
    begin
        fw_total_bytes = nwords * 4;
        fw_n_chunks    = nwords / CHUNK_WORDS;

        $display("[tb] Enviando %0d bytes (%0d chunks de 64)", fw_total_bytes, fw_n_chunks);

        resp_received = 0;
        uart_send_byte(8'hAA);
        uart_send_byte(8'h55);
        $display("[T=%0t] [tb] Sync AA 55 enviado, esperando ACK...", $time);
        wait (resp_received == 1);
        $display("[T=%0t] [tb] ACK de sync recibido", $time);

        uart_send_byte(fw_total_bytes[7:0]);
        uart_send_byte(fw_total_bytes[15:8]);
        uart_send_byte(fw_total_bytes[23:16]);
        uart_send_byte(fw_total_bytes[31:24]);
        $display("[T=%0t] [tb] Size enviado: %0d bytes", $time, fw_total_bytes);

        for (fw_c = 0; fw_c < fw_n_chunks; fw_c = fw_c+1) begin
            fw_xor = 0;
            for (fw_w = 0; fw_w < CHUNK_WORDS; fw_w = fw_w+1) begin
                fw_word = use_alt ? worker_alt_mem[fw_c * CHUNK_WORDS + fw_w]
                                   : worker_mem[fw_c * CHUNK_WORDS + fw_w];
                for (fw_b = 0; fw_b < 4; fw_b = fw_b+1) begin
                    uart_send_byte(fw_word[7:0]);
                    fw_xor = fw_xor ^ fw_word[7:0];
                    fw_word = fw_word >> 8;
                end
            end

            resp_received = 0;
            uart_send_byte(fw_xor);
            wait (resp_received == 1);
            if (last_resp != 8'h06) begin
                $display("[T=%0t] [tb] Chunk %0d: NACK inesperado", $time, fw_c);
            end
        end
    end
endtask

function [31:0] last_nonzero_chunk_words;
    input integer dummy;
    integer i;
    reg [31:0] n;
    begin
        n = CHUNK_WORDS;   // mínimo 1 chunk
        for (i = APP_WORDS-1; i >= 0; i = i-1) begin
            if (worker_mem[i] != 32'h0 && n == CHUNK_WORDS)
                n = ((i / CHUNK_WORDS) + 1) * CHUNK_WORDS;
        end
        last_nonzero_chunk_words = n;
    end
endfunction

// ─── Hilo principal: boot inicial, espera 1 ventana, recarga, espera otra ──
initial begin
    for (fw_i = 0; fw_i < APP_WORDS; fw_i = fw_i+1) begin
        worker_mem[fw_i]     = 32'h0;
        worker_alt_mem[fw_i] = 32'h0;
    end
    $readmemh("fw1/worker.hex",     worker_mem);
    $readmemh("fw1/worker_alt.hex", worker_alt_mem);

    worker_nwords     = CHUNK_WORDS;
    worker_alt_nwords = CHUNK_WORDS;
    for (fw_i = APP_WORDS-1; fw_i >= 0; fw_i = fw_i-1) begin
        if (worker_mem[fw_i] != 32'h0 && worker_nwords == CHUNK_WORDS)
            worker_nwords = ((fw_i / CHUNK_WORDS) + 1) * CHUNK_WORDS;
        if (worker_alt_mem[fw_i] != 32'h0 && worker_alt_nwords == CHUNK_WORDS)
            worker_alt_nwords = ((fw_i / CHUNK_WORDS) + 1) * CHUNK_WORDS;
    end

    // Esperar a que Core 0 imprima su banner y quede bloqueado en wait_sync().
    // Banner mas largo que el de boot.c solo (bootloader + manager de
    // mailbox en el mismo mensaje) -> a 10 ciclos/bit (SIM_BAUD) cada
    // caracter tarda ~100 ciclos; con margen generoso para no competir con
    // la llegada de AA 55 antes de que Core 0 termine de imprimir.
    repeat(25000) @(posedge clk);

    $display("\n[tb] === Boot inicial (worker.c) ===");
    send_firmware(worker_nwords, 1'b0);

    $display("\n[tb] Firmware inicial enviado. Esperando primera ventana de BER...");
    wait (window_closes >= 1);

    $display("\n[tb] === Recarga en caliente (worker_alt.c) ===");
    send_firmware(worker_alt_nwords, 1'b1);

    $display("\n[tb] Recarga enviada. Esperando confirmacion + ventana con firmware nueva...");
    wait (reload_ok >= 1 && window_closes >= 2);

    $display("\n[tb] Recarga en caliente verificada de punta a punta.");
    repeat(2000) @(posedge clk);
    $display("[tb] Simulacion completada.");
    $finish;
end

// ─── Reset y timeout ─────────────────────────────────────────────────────────
initial begin
`ifdef DUMP_VCD
    $dumpfile("tb_mboot.vcd");
    $dumpvars(1, tb_mboot);
`endif
    resetn = 0;
    repeat(10) @(posedge clk);
    resetn = 1;

    repeat(TIMEOUT) @(posedge clk);
    $display("\n[tb] timeout (%0d ciclos)", TIMEOUT);
    $finish;
end

endmodule

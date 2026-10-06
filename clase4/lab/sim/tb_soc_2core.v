// =============================================================================
// tb_soc_2core.v — Testbench para soc_2core (Jornada 4 — Mailbox 2-Core)
//
// Usa BAUD=1_000_000 para acelerar simulación (100 ciclos/bit a 100 MHz).
// Captura la salida UART del Core 0 y la imprime como texto en consola.
// Detecta trap en cualquiera de los dos núcleos.
// =============================================================================
`timescale 1ns/1ps

module tb_soc_2core;

    localparam CLK_HZ   = 100_000_000;
    localparam SIM_BAUD = 1_000_000;
    localparam BIT_CYC  = CLK_HZ / SIM_BAUD;   // = 100

    reg  clk, resetn;
    wire [3:0] led;
    wire tx, trap;

    wire m0_valid = dut.m0_valid;
    wire m0_ready = dut.m0_ready;
    wire [31:0] m0_addr = dut.m0_addr;
    wire [31:0] m0_wdata = dut.m0_wdata;
    wire [31:0] m0_rdata = dut.m0_rdata;
    wire [3:0] m0_wstrb = dut.m0_wstrb;
    wire [3:0] sw = dut.sw;
    wire [31:0] m1_addr = dut.m1_addr;
    wire [31:0] m1_wdata = dut.m1_wdata;
    wire [31:0] mbx_rdata1 = dut.mbx_rdata1;

    soc_2core #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (SIM_BAUD)
    ) dut (
        .clk    (clk),
        .resetn (resetn),
        .led    (led),
        .sw     (4'h8),   // nivel 8 -> periodo 1021 (mismo BER ya documentado)
        .rx     (1'b1),
        .tx     (tx),
        .trap   (trap)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_soc_2core.vcd");
        $dumpvars(1, tb_soc_2core);  // solo señales top-level (dump completo es ~GB y hace la sim lentísima)
    end

    initial begin
        resetn = 0;
        repeat (20) @(posedge clk);
        resetn = 1;
    end

    // -------------------------------------------------------------------------
    // Decodificador serie: captura 1 byte del pin TX (8N1)
    // -------------------------------------------------------------------------
    task uart_capture_byte;
        output [7:0] data_out;
        integer i;
        begin
            @(negedge tx);
            repeat (BIT_CYC / 2) @(posedge clk);
            data_out = 8'h00;
            for (i = 0; i < 8; i = i + 1) begin
                repeat (BIT_CYC) @(posedge clk);
                data_out[i] = tx;
            end
            repeat (BIT_CYC) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Captura e imprime la salida TX del Core 0
    // -------------------------------------------------------------------------
    reg [7:0] rx_byte;
    integer   char_count;

    initial begin
        char_count = 0;
        @(posedge resetn);
        $display("\n[tb] inicio captura UART (Core 0):\n");
        forever begin
            uart_capture_byte(rx_byte);
            $write("%c", rx_byte);
            // $write(rx_byte);
            // $display("%c", rx_byte);
            char_count = char_count + 1;
            if (char_count >= 600) begin
                $display("\n[tb] captura completa (%0d chars)", char_count);
                $finish;
            end
        end
    end

    initial begin
        #400_000_000;   // 400 ms
        $display("\n[tb] timeout");
        $finish;
    end

    always @(posedge trap) begin
        $display("\n[tb] TRAP detectada en ciclo %0d", $time / 10);
        $finish;
    end

endmodule

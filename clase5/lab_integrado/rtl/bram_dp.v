// =============================================================================
// bram_dp.v — BRAM de doble puerto (True Dual-Port)
// Jornada 4 — SoC 2-Core con Mailbox
//
// Puerto A → Core 0 / Puerto B → Core 1
// Usa READ_FIRST (salida = dato anterior a la escritura).
// Sin árbitro hardware: el protocolo software garantiza que cada núcleo
// escribe en sus propias palabras del mailbox.
// =============================================================================

module bram_dp #(
    parameter DATA_W = 32,
    parameter ADDR_W = 6    // 64 palabras = 256 bytes
)(
    // Puerto A (Core 0)
    input                   clka,
    input                   ena,
    input                   wea,
    input  [ADDR_W-1:0]     addra,
    input  [DATA_W-1:0]     dina,
    output reg [DATA_W-1:0] douta,

    // Puerto B (Core 1)
    input                   clkb,
    input                   enb,
    input                   web,
    input  [ADDR_W-1:0]     addrb,
    input  [DATA_W-1:0]     dinb,
    output reg [DATA_W-1:0] doutb
);
    reg [DATA_W-1:0] mem [(1<<ADDR_W)-1:0];

    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            mem[i] = 32'h0;
    end

    always @(posedge clka)
        if (ena) begin
            if (wea) mem[addra] <= dina;
            douta <= mem[addra];
        end

    always @(posedge clkb)
        if (enb) begin
            if (web) mem[addrb] <= dinb;
            doutb <= mem[addrb];
        end

endmodule

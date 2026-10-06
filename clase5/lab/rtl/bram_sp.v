// =============================================================================
// bram_sp.v — BRAM Single-Port con byte enables (inferencia RAMB36E1)
// Jornada 5 — Bootloader PRBS/BER
// =============================================================================

module bram_sp #(
    parameter DATA_W   = 32,
    parameter ADDR_W   = 12,
    parameter INIT_FILE = ""
)(
    input  wire              clk,
    input  wire              ena,
    input  wire [3:0]        wea,    // byte enables (b3=byte3..b0=byte0)
    input  wire [ADDR_W-1:0] addr,
    input  wire [DATA_W-1:0] din,
    output reg  [DATA_W-1:0] dout
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    generate
        if (INIT_FILE != "") begin
            initial $readmemh(INIT_FILE, mem);
        end
    endgenerate

    // Byte-enable write + read-first (compatible con inferencia RAMB36E1)
    always @(posedge clk) begin
        if (ena) begin
            if (wea[0]) mem[addr][ 7: 0] <= din[ 7: 0];
            if (wea[1]) mem[addr][15: 8] <= din[15: 8];
            if (wea[2]) mem[addr][23:16] <= din[23:16];
            if (wea[3]) mem[addr][31:24] <= din[31:24];
            dout <= mem[addr];
        end
    end
endmodule

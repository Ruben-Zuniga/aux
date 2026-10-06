// =============================================================================
// boot.c — Firmware de bootloader (Core 0)
// Jornada 5 — Bootloader PRBS/BER
//
// Protocolo de carga UART (chunk-based, con sincronización y reintento):
//   Host → FPGA: [AA 55 sync]
//   FPGA → Host: ACK (0x06)
//   Host → FPGA: [4 bytes tamaño LE]
//   Host → FPGA: [chunk0: 64 bytes + 1 XOR] ...
//   FPGA → Host: ACK (0x06) si checksum correcto, NACK (0x15) si falla
//   Host: ante un NACK, reenvía el MISMO chunk (hasta MAX_RETRIES veces)
//   FPGA: si no llega la sincronización en TIMEOUT_CYCLES, aborta (ver
//         wait_sync) — una vez sincronizado, la transferencia es continua
//
// Mapa de memoria Core 0:
//   0x000000  BRAM0 (este firmware)
//   0x100000  Ventana de boot → BRAM1 de Core 1
//   0x300000  UART_DATA / UART_STATUS
//   0x310000  SYSCTRL: bit[0]=liberar Core1, bits[7:4]=LED
// =============================================================================

#include <stdint.h>
#include "uart.h"

#define SYSCTRL         (*(volatile uint32_t*)0x310000)
#define SYSCTRL_LED(x)  ((uint32_t)(x) << 4)
#define SYSCTRL_REL_C1  (1u << 0)

#define CORE1_BASE  ((volatile uint32_t*)0x100000)

#define CHUNK_SIZE   64
#define ACK          0x06
#define NACK         0x15
#define SYNC_A       0xAA
#define SYNC_B       0x55
#define MAX_RETRIES  5

#define TIMEOUT_CYCLES  (100000000UL * 5)   /* ~5 s a 100 MHz */

static inline uint32_t rdcycle(void) {
    uint32_t v;
    asm volatile("rdcycle %0" : "=r"(v));
    return v;
}

// Recibe 1 byte con timeout (dado). Retorna 0 y *out=byte si llega a
// tiempo, -1 si no.
static int uart_getc_timeout(uint8_t *out)
{
    uint32_t t0 = rdcycle();
    while (!uart_rx_ready()) {
        if ((rdcycle() - t0) > TIMEOUT_CYCLES)
            return -1;
    }
    *out = (uint8_t)(UART_DATA & 0xFF);
    return 0;
}

// Espera el header de sincronización AA 55 (dado) y responde ACK para
// confirmar que el bootloader está listo para recibir. Es el único punto
// donde el firmware puede esperar indefinidamente (el host todavía no
// arrancó la transferencia), por eso es el único lugar con timeout.
static int wait_sync(void)
{
    uint8_t b;
    for (;;) {
        if (uart_getc_timeout(&b) < 0) return -1;
        if (b == SYNC_A) break;
    }
    if (uart_getc_timeout(&b) < 0) return -1;
    if (b != SYNC_B) return -1;
    uart_putc(ACK);
    return 0;
}

// ─── TODO 1: Carga de firmware vía UART ──────────────────────────────────────
// Recibe `size` bytes en chunks de 64 con checksum XOR por chunk.
// Escribe los datos en `base` como words de 32 bits (little-endian).
//
// El bucle "for (;;)" de reintento ya está dado: si el checksum no
// coincide, se envía NACK y se vuelve a intentar el MISMO chunk (el host
// lo reenvía) hasta MAX_RETRIES veces. Tu tarea es completar la recepción
// y el armado de cada chunk:
//
//   1. Recibir CHUNK_SIZE bytes (64, SIEMPRE -- ver nota abajo) con
//      uart_getc() y acumular el XOR de todos ellos
//   2. Recibir 1 byte de checksum del host con uart_getc()
//   3. Si coincide (ya dado el "if"): ensamblar words little-endian y
//      escribir en base[] SOLO los primeros `len` bytes de buf[], luego
//      enviar ACK(0x06) (ya dado)
//
// OJO con el paso 1: el host (loader.py) SIEMPRE manda CHUNK_SIZE bytes
// por chunk -- el último, si `size` no es múltiplo de CHUNK_SIZE, viene
// relleno con ceros hasta completarlo, y el XOR que calcula el host se
// hace sobre esos CHUNK_SIZE bytes ya rellenos. Si acá se leyeran solo
// `len` bytes (menos que CHUNK_SIZE en el último chunk), sobrarían bytes
// de relleno sin consumir en el buffer de UART, y el próximo uart_getc()
// -- el que debería traer el checksum -- leería uno de esos bytes de
// relleno en su lugar, desincronizando todo el resto de la carga.
//
// Pista para ensamblar un word de 4 bytes buf[i..i+3]:
//   uint32_t w = (uint32_t)buf[i+0]
//              | (uint32_t)buf[i+1] << 8
//              | (uint32_t)buf[i+2] << 16
//              | (uint32_t)buf[i+3] << 24;
//   base[(offset + i) / 4] = w;
//
// IMPORTANTE: la UART no tiene FIFO — Core 0 debe leer sin demora. Por
// eso esta recepción usa uart_getc() (sin timeout): una vez que el host
// empezó a mandar un chunk, los bytes llegan pegados uno detrás del otro.
//
// Notá que buf[] vive en la pila de Core 0 (BRAM0), no en la memoria
// destino: los bytes se juntan ahí primero y solo se escriben en base[]
// si el checksum de TODO el chunk cierra (paso 3). Nunca se escribe byte
// a byte a medida que llega — así un chunk con checksum inválido se
// descarta entero sin dejar la BRAM destino a medio escribir.
static int boot_load(volatile uint32_t *base, uint32_t size)
{
    uint32_t n_chunks = (size + CHUNK_SIZE - 1) / CHUNK_SIZE;
    uint32_t offset   = 0;

    for (uint32_t c = 0; c < n_chunks; c++) {
        uint32_t len = (offset + CHUNK_SIZE <= size)
                       ? CHUNK_SIZE : (size - offset);
        int retries = 0;

        for (;;) {
            uint8_t buf[CHUNK_SIZE];
            uint8_t xor_calc = 0;

            // TODO: recibir los CHUNK_SIZE bytes del chunk (uart_getc()),
            //       SIEMPRE los 64 (no `len` -- ver nota arriba del
            //       último chunk relleno con ceros), y acumular el XOR
            //       en xor_calc
            for (int i = 0; i < CHUNK_SIZE; i++){
                buf[i] = uart_getc();
                xor_calc ^= buf[i];
            }

            // TODO: recibir 1 byte de checksum del host en xor_recv
            uint8_t xor_recv = uart_getc();

            if (xor_calc == xor_recv) {
                // TODO: ensamblar words little-endian y escribir en
                //       base[] -- solo los primeros `len` bytes de buf[]
                for (int i = 0; i < len; i++){
                    // base[i] = buf[i];
                    uint32_t w = (uint32_t)buf[i+0]
                               | (uint32_t)buf[i+1] << 8
                               | (uint32_t)buf[i+2] << 16
                               | (uint32_t)buf[i+3] << 24;
                    base[(offset + i) / 4] = w;
                }
                uart_putc(ACK);
                break;   // chunk OK: pasar al siguiente
            } else {
                uart_putc(NACK);
                retries++;
                if (retries >= MAX_RETRIES) {
                    uart_puts("ERROR — reintentos agotados en un chunk.\r\n");
                    return -1;
                }
                // el host reenvía el mismo chunk; volvemos a intentarlo
            }
        }
        offset += len;
    }
    return 0;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
// Loop de por vida (dado): cada vuelta espera un handshake AA 55 y carga un
// firmware nuevo en Core 1. La primera vuelta es el boot inicial; las
// siguientes son recargas en caliente.
//
// OJO: el write que retiene a Core 1 en reset (SYSCTRL_LED(0x1), que
// reasigna bit 0 = REL_C1 a 0 sin tocarlo explícitamente) va DESPUÉS de
// wait_sync(), nunca antes -- si se hiciera al principio del loop, la
// vuelta que sigue a una liberación exitosa retendría a Core 1 de nuevo
// casi al instante, antes de que llegue a ejecutar una sola instrucción
// de la nueva imagen.
void main(void)
{
    uart_puts("\r\n=== Bootloader SoC PicoRV32 — Jornada 5 ===\r\n");
    SYSCTRL = SYSCTRL_LED(0x1);   // LED[0]: bootloader activo (Core 1 ya en reset por power-on)

    for (;;) {
        uart_puts("Listo. Esperando sincronizacion (AA 55)...\r\n");

        if (wait_sync() < 0) {
            uart_puts("TIMEOUT esperando sincronizacion.\r\n");
            // uart_puts("TIMEOUT esperando sincronizacion. Reiniciar.\r\n");
            // while (1);
        }

        // Recién acá, con un AA 55 real confirmado, retenemos a Core 1 (de
        // nuevo, si ya estaba corriendo) y reabrimos la ventana de boot.
        SYSCTRL = SYSCTRL_LED(0x1);

        // ─── TODO 2: Recibir tamaño del firmware (4 bytes, little-endian) ─────
        // Leer 4 bytes con uart_getc() y combinar en un uint32_t:
        //   size = byte0 | byte1<<8 | byte2<<16 | byte3<<24
        // IMPORTANTE: sin imprimir nada antes — la UART no tiene FIFO.
        uint32_t size = 0;
        uint8_t byte[4] = {0};

        for (int i = 0; i < 4; i++){
            byte[i] = uart_getc();
        }
        size = byte[0] | (byte[1] << 8) | (byte[2] << 16) | (byte[3] << 24);

        // ─── TODO 3: Llamar a boot_load() e imprimir resultado ───────────────
        // IMPORTANTE: llamar a boot_load() inmediatamente después de recibir
        // el tamaño, sin imprimir nada antes (la UART no tiene FIFO).
        //
        // Si éxito: imprimir "Cargados X bytes OK — liberando Core 1\r\n"
        //           y escribir SYSCTRL para encender LED[1:0] y liberar Core 1
        // Si error: imprimir "ERROR — carga fallida. Core 1 queda retenido.\r\n"
        //           y quedarse en bucle infinito (while(1);)
        if (boot_load(CORE1_BASE, size) < 0){
            uart_puts("ERROR - carga fallida. Core 1 queda retenido.\r\n");
            while(1);
        }
        else{
            uart_puts("Cargados ");
            uart_print_uint(size);
            uart_puts(" bytes OK - liberando Core 1.\r\n");
            SYSCTRL = SYSCTRL_LED(0x0);
        }

        // No hacer "while(1);" acá al final: dejar que el for(;;) vuelva a
        // wait_sync() es lo que permite make load-alt sin resintetizar ni
        // resetear la placa.
    }
}

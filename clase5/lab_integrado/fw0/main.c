// =============================================================================
// main.c — Firmware Core 0: bootloader + manager de mailbox PRBS/BER
// Jornada extra — mailbox (Jornada 4) que sobrevive a la recarga en caliente
// del firmware de Core 1 (Jornada 5)  [ESQUELETO]
//
// wait_sync()/boot_load()/load_and_release() son las mismas funciones que ya
// escribiste en boot.c de Jornada 5 (acá vienen dadas). El loop de manager
// de mailbox de más abajo -- incluida la recarga en caliente -- es el mismo
// que ya escribiste en fw0/main.c de Jornada 4 (también dado tal cual). Lo
// único que falta sos vos: encadenar las dos cosas en main() (ver TODO 1).
//
// Core 0 hace tres cosas, en este orden:
//   1. Boot inicial: espera el handshake AA 55 por UART (idéntico al de
//      boot.c de Jornada 5) y carga fw1/worker.bin en la BRAM de Core 1.
//   2. Libera Core 1 y entra al mismo loop de manager de mailbox de
//      Jornada 4: genera bloques PRBS, los deja en el mailbox, espera el
//      resultado de Core 1 y reporta BER por UART cada WINDOW_BLOCKS.
//   3. En cada vuelta del loop, con el mailbox en reposo (MBX_STATE ==
//      MBX_IDLE, el único punto donde es seguro tocar Core 1), chequea sin
//      bloquear si llegó un nuevo handshake AA 55 por UART. Si llegó: pausa
//      Core 1 (mismo registro SYSCTRL, no es de una sola vez), vuelve a
//      correr el mismo protocolo de carga, y libera Core 1 de nuevo con
//      firmware nuevo — sin resintetizar y sin perder el mailbox.
//
// El propio host (host/loader.py) no cambia nada: el comando de recarga es
// EL MISMO handshake que ya usa para la carga inicial.
//
// Ojo con esto (encontrado simulando, no a simple vista): a diferencia del
// boot inicial -- donde Core 0 no hace OTRA cosa más que sondear la UART en
// wait_sync() --, acá el chequeo pasa UNA sola vez por bloque, y un bloque
// entero (generar 1024 bits de PRBS + ida y vuelta del mailbox) puede tardar
// mucho más que el tiempo entre los dos bytes AA y 55, que el host manda
// juntos en un solo write(). Si los dos llegan antes de que este chequeo
// tenga oportunidad de leer el primero, la UART (sin FIFO, un solo byte de
// latch) pisa el primero con el segundo. La solución NO es sondear más
// seguido (frágil, depende de cuánto tarde el resto del loop) sino no
// importarle CUÁL de los dos bytes sobrevivió: cualquiera de los dos sirve
// como disparador, porque el byte que quede en el latch se queda ahí
// esperando indefinidamente (el host no manda nada más hasta ver el ACK) --
// ver do_reload_trigger() más abajo.
// =============================================================================

#include <stdint.h>
#include "uart.h"
#include "mailbox_prbs.h"
#include "prbs.h"
#include "sw.h"

#define SYSCTRL         (*(volatile uint32_t*)0x310000)
#define SYSCTRL_LED(x)  ((uint32_t)(x) << 4)
#define SYSCTRL_REL_C1  (1u << 0)
#define CORE1_BASE      ((volatile uint32_t*)0x100000)

#define GPIO (*(volatile uint32_t *)0x00200000)

#define CHUNK_SIZE   64
#define ACK          0x06
#define NACK         0x15
#define SYNC_A       0xAA
#define SYNC_B       0x55
#define MAX_RETRIES  5

#define TIMEOUT_CYCLES  (100000000UL * 5)   /* ~5 s a 100 MHz */
#define DRAIN_TIMEOUT_CYCLES  100000UL      /* ~1 ms a 100 MHz */

#ifdef SIM
#  define DELAY_CYCLES  200UL
#else
#  define DELAY_CYCLES  5000000UL   /* ~50 ms a 100 MHz, por bloque */
#endif

static inline uint32_t rdcycle(void) {
    uint32_t v;
    asm volatile("rdcycle %0" : "=r"(v));
    return v;
}

static void delay_cycles(uint32_t n) {
    uint32_t t0 = rdcycle();
    while ((rdcycle() - t0) < n);
}

// Recibe 1 byte con timeout. Retorna 0 y *out=byte si llega a tiempo, -1 si no.
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

// ─── Protocolo de carga UART (idéntico a boot.c de Jornada 5) ───────────────
// [4 bytes tamaño LE] + chunks de 64 bytes con XOR y ACK/NACK + reintento.
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

            // El host SIEMPRE manda CHUNK_SIZE bytes por chunk (el último,
            // si `size` no es múltiplo, viene relleno con ceros y el XOR
            // del host se calcula sobre esos CHUNK_SIZE ya rellenos) -- hay
            // que leer los CHUNK_SIZE completos, no `len`, o el próximo
            // uart_getc() (el del checksum) lee un byte de relleno en vez
            // del checksum real y desincroniza el resto de la carga.
            for (uint32_t i = 0; i < CHUNK_SIZE; i++) {
                uint8_t b = (uint8_t)uart_getc();
                buf[i]    = b;
                xor_calc ^= b;
            }

            uint8_t xor_recv = (uint8_t)uart_getc();

            if (xor_calc == xor_recv) {
                for (uint32_t i = 0; i < len; i += 4) {
                    uint32_t w = (uint32_t)buf[i+0]
                               | (uint32_t)buf[i+1] << 8
                               | (uint32_t)buf[i+2] << 16
                               | (uint32_t)buf[i+3] << 24;
                    base[(offset + i) / 4] = w;
                }
                uart_putc(ACK);
                break;
            } else {
                uart_putc(NACK);
                retries++;
                if (retries >= MAX_RETRIES) {
                    uart_puts("ERROR -- reintentos agotados en un chunk.\r\n");
                    return -1;
                }
            }
        }
        offset += len;
    }
    return 0;
}

// Espera el header de sincronización AA 55 (tolera bytes previos sueltos:
// resincroniza buscando 0xAA) y responde ACK. Idéntica a wait_sync() de
// boot.c de Jornada 5 -- se usa tal cual para el boot inicial.
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

// Ya con el sync confirmado (ACK enviado): recibe el tamaño y carga el
// firmware nuevo en BRAM1 de Core 1. Retiene Core 1 en reset durante toda
// la carga y lo libera recién si sale todo bien -- si falla, lo deja
// retenido (mismo criterio que boot.c). Se usa tanto para el boot inicial
// como para cada recarga en caliente posterior: es la MISMA rutina.
static int load_and_release(void)
{
    SYSCTRL = SYSCTRL_LED(0x1);   // LED[0]: carga en curso, Core 1 retenido

    uint32_t size;
    size  = (uint32_t)(uint8_t)uart_getc();
    size |= (uint32_t)(uint8_t)uart_getc() << 8;
    size |= (uint32_t)(uint8_t)uart_getc() << 16;
    size |= (uint32_t)(uint8_t)uart_getc() << 24;

    int err = boot_load(CORE1_BASE, size);

    if (err == 0) {
        uart_puts("Cargados ");
        uart_print_uint(size);
        uart_puts(" bytes OK -- liberando Core 1\r\n");
        MBX_STATE = MBX_IDLE;   // por si quedaba un bloque a medio terminar
        SYSCTRL = SYSCTRL_LED(0x3) | SYSCTRL_REL_C1;
        return 0;
    }

    uart_puts("ERROR -- carga fallida. Core 1 queda retenido.\r\n");
    return -1;
}

static uint32_t gen_word_with_errors(prbs_gen_t *g, uint32_t *bit_count,
                                      uint32_t err_period) {
    uint32_t w = 0;
    for (int i = 0; i < 32; i++) {
        uint32_t bit = prbs_gen_bit(g);
        (*bit_count)++;
        if (err_period && (*bit_count % err_period) == 0)
            bit ^= 1u;
        w |= bit << i;
    }
    return w;
}

void main(void)
{
    uart_puts("\r\n=== Jornada extra: mailbox + bootloader ===\r\n");
    uart_puts("Boot inicial: esperando firmware de Core 1 (AA 55)...\r\n");

    // ═══════════════════════════════════════════════════════════════════════
    // TODO 1 — Boot inicial de Core 1
    //   Antes de entrar al loop de manager de mailbox, Core 1 tiene que
    //   tener firmware cargado y estar liberado de reset. Encadená las dos
    //   funciones ya dadas (idénticas a las de boot.c de Jornada 5):
    //
    //     1. wait_sync() -- si devuelve <0 (timeout), no llegó nadie a
    //        conectarse: avisar y quedarse en while(1), no hay con qué seguir.
    //     2. load_and_release() -- si devuelve !=0 (carga fallida), Core 1
    //        queda retenido en reset (load_and_release ya lo deja así); acá
    //        tampoco hay con qué seguir: quedarse en while(1).
    //
    //   Si las dos salen bien, seguí de largo hacia el manager de abajo.
    // ═══════════════════════════════════════════════════════════════════════
    if (wait_sync() < 0) {
        uart_puts("TIMEOUT esperando sincronizacion. Reiniciar.\r\n");
        while (1);
    }
    load_and_release();

    // ─── Manager de mailbox (Jornada 4), con recarga en caliente ───────────
    uart_puts("Bloque = "); uart_print_uint(BLOCK_WORDS * 32); uart_puts(" bits");
    uart_puts("  |  Ventana = "); uart_print_uint(WINDOW_BITS); uart_puts(" bits\r\n\r\n");

    prbs_gen_t gen;
    prbs_gen_init(&gen, 0x1ACEu);
    uint32_t bit_count = 0;

    uint32_t window_blocks = 0;
    uint32_t window_errors = 0;
    uint32_t block_num     = 0;

    while (1) {
        // Único punto seguro para tocar Core 1: el mailbox está en reposo,
        // no hay ningún bloque a medio procesar.
        while (MBX_STATE != MBX_IDLE);

        // Comando de recarga: no bloqueante, no interfiere con el tráfico
        // normal porque Core 0 nunca lee UART en este loop salvo acá.
        if (uart_rx_ready()) {
            uint8_t cmd = (uint8_t)uart_getc();
            if (cmd == SYNC_A || cmd == SYNC_B) {
                // Cualquiera de los dos alcanza como disparador (ver nota
                // arriba). Si el OTRO byte del par ya llegó también, drenarlo
                // con un timeout corto antes de ACKear -- si no, el resto
                // del protocolo (tamaño + chunks, que arranca recién después
                // del ACK) queda corrido 1 byte.
                uint8_t extra;
                uint32_t td = rdcycle();
                while (!uart_rx_ready() && (rdcycle() - td) < DRAIN_TIMEOUT_CYCLES);
                if (uart_rx_ready()) extra = (uint8_t)uart_getc();
                (void)extra;

                // El mensaje va ANTES del ACK, no después: el host arranca a
                // mandar tamaño+chunks apenas ve el ACK, y la UART no tiene
                // FIFO de recepción. Si el ACK saliera primero, estos ~35
                // bytes de uart_puts() (bloqueante, sin sondear RX mientras
                // transmite) se solaparían con los primeros bytes del
                // tamaño, perdiéndolos -- boot_load() terminaría leyendo un
                // tamaño corrupto y colgado en un uart_getc() que nunca
                // vuelve a tener con qué resincronizar.
                uart_puts("\r\n[C0] Recarga en caliente solicitada -- ");
                uart_puts("pausando mailbox\r\n");
                uart_putc(ACK);   // confirma el sync, igual que wait_sync()
                load_and_release();
                window_blocks = 0;   // firmware nueva: ventana arranca de cero
                window_errors = 0;
                continue;
            }
            // no era un byte de sync: se descarta y se sigue el loop
        }

        uint32_t err_period = sw_err_period();

        for (uint32_t i = 0; i < BLOCK_WORDS; i++)
            MBX_DATA[i] = gen_word_with_errors(&gen, &bit_count, err_period);

        GPIO = block_num & 0xF;
        MBX_STATE = MBX_WORK;

        while (MBX_STATE != MBX_DONE);
        uint32_t block_errors = MBX_ERRORS;
        MBX_STATE = MBX_IDLE;

        window_blocks++;
        window_errors += block_errors;
        block_num++;

        if (window_blocks >= WINDOW_BLOCKS) {
            uint32_t ppm = (uint32_t)(((uint64_t)window_errors * 1000000ULL) / WINDOW_BITS);
            uart_puts("[C0] ventana cerrada: ");
            uart_print_uint(window_errors);
            uart_puts(" errores / ");
            uart_print_uint(WINDOW_BITS);
            uart_puts(" bits  -> BER ~= ");
            uart_print_uint(ppm);
            uart_puts(" ppm  (SW="); uart_print_uint(sw_read()); uart_puts(")\r\n");

            window_blocks = 0;
            window_errors = 0;
        }

        delay_cycles(DELAY_CYCLES);
    }
}

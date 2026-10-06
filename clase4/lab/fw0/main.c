// =============================================================================
// main.c — Firmware Core 0: manager UART + generador PRBS (Jornada 4)
// [ESQUELETO PARA ESTUDIANTES — completar las secciones marcadas con TODO]
//
// Core 0 genera un stream PRBS-15 (ver funda/comun/DISENO_PRBS_BER.txt),
// inyecta errores a una tasa configurable, y lo escribe al mailbox en
// bloques de BLOCK_WORDS palabras. Core 1 devuelve cuántos bits detectó
// mal en cada bloque. Cada WINDOW_BLOCKS bloques, Core 0 cierra una
// "ventana" de medición y reporta el BER acumulado por UART.
//
// La tasa de inyección de error no es una constante fija: se lee en vivo
// de los switches SW[3:0] (ver sw.h) al cierre de cada bloque, así que
// cambia sin recompilar ni resintetizar.
// =============================================================================

#include <stdint.h>
#include "uart.h"
#include "mailbox_prbs.h"
#include "prbs.h"
#include "sw.h"

#define GPIO (*(volatile uint32_t *)0x00200000)

static inline uint32_t rdcycle(void) {
    uint32_t v;
    asm volatile("csrr %0, cycle" : "=r"(v));
    return v;
}

static void delay_cycles(uint32_t n) {
    uint32_t t0 = rdcycle();
    while ((rdcycle() - t0) < n);
}

// #define SIM
#ifdef SIM
#  define DELAY_CYCLES  200UL
#else
#  define DELAY_CYCLES  5000000UL   /* ~50 ms a 100 MHz, por bloque */
#endif

// -----------------------------------------------------------------------
// TODO 1 — gen_word_with_errors()
//   Generar una palabra de 32 bits: por cada uno de los 32 bits,
//     - sacar un bit de PRBS con prbs_gen_bit(g)  (ver prbs.h)
//     - incrementar *bit_count
//     - si err_period != 0 y (*bit_count % err_period) == 0, invertir
//       el bit (bit ^= 1) antes de empaquetarlo — así se inyecta un
//       error cada err_period bits, en promedio
//   Empaquetar los bits en w con bit i en la posición i (w |= bit << i).
// -----------------------------------------------------------------------
static uint32_t gen_word_with_errors(prbs_gen_t *g, uint32_t *bit_count,
                                      uint32_t err_period) {
    // TODO 1: completar. Por ahora devuelve 0 (no compila el flujo real).
    // (void)g; (void)bit_count; (void)err_period;

    uint32_t word = 0u;
    uint32_t bit;

    for (uint32_t idx_bit = 0; idx_bit < 32; idx_bit++)
    {
        bit = prbs_gen_bit(g);
        *bit_count += 1u;

        if (err_period != 0 && (*bit_count % err_period == 0))
            bit ^= 1;

        word |= bit << idx_bit;
    }

    return word;
}

void main(void) {
    uart_puts("\r\n=== Jornada 4: PRBS/BER por mailbox (BERT de 2 cores) ===\r\n");
    uart_puts("Core 0: generador PRBS + manager UART  |  Core 1: checker\r\n");
    uart_puts("Bloque = "); uart_print_uint(BLOCK_WORDS * 32); uart_puts(" bits");
    uart_puts("  |  Ventana = "); uart_print_uint(WINDOW_BITS); uart_puts(" bits\r\n\r\n");

    prbs_gen_t gen;
    prbs_gen_init(&gen, 0x1ACEu);
    uint32_t bit_count = 0;
    uint32_t err_period = 0;

    uint32_t block_errors = 0;
    uint32_t window_blocks = 0;
    uint32_t window_errors = 0;

    uint32_t ppm = 0;
    uint32_t aux = 0;

    while (1) {

        // Esperar a que el mailbox quede libre
        while (MBX_STATE != MBX_IDLE);

        // -------------------------------------------------------------
        // TODO 2 — generar y enviar un bloque
        //   a) Leer la tasa de inyección en vivo: sw_err_period() (sw.h).
        //      Se lee de nuevo en cada bloque para que cambiar los
        //      switches en la placa tenga efecto sin recompilar.
        //   b) Llenar MBX_DATA[0..BLOCK_WORDS-1] llamando a
        //      gen_word_with_errors() por cada palabra.
        //   c) Escribir GPIO = block_num & 0xF (mismo patrón que
        //      Jornada 2/3: los LEDs muestran los bits bajos del
        //      contador de bloques).
        //   d) Señalizar el bloque: MBX_STATE = MBX_WORK.
        // -------------------------------------------------------------
        err_period = sw_err_period();

        for (uint32_t idx_block = 0; idx_block < BLOCK_WORDS; idx_block++){
            MBX_DATA[idx_block] = gen_word_with_errors(&gen, &bit_count, err_period);
        }
        
        MBX_STATE = MBX_WORK;
        GPIO = window_blocks & 0xF;
        
        // Esperar a que Core 1 termine de chequear el bloque (polling)
        while (MBX_STATE != MBX_DONE);
        block_errors = MBX_ERRORS;
        MBX_STATE = MBX_IDLE;

        window_blocks = window_blocks + 1u;
        window_errors = window_errors + block_errors;

        if (window_blocks >= WINDOW_BLOCKS) {
            // ---------------------------------------------------------
            // TODO 3 — cerrar la ventana y reportar por UART
            //   Calcular el BER en ppm:
            //     ppm = (window_errors * 1000000) / WINDOW_BITS
            //   OJO: usar uint64_t en la multiplicación intermedia para
            //   no desbordar 32 bits (WINDOW_BITS es constante de
            //   compilación, así que el compilador resuelve la división
            //   sin necesitar __udivdi3 — no hay libgcc en un firmware
            //   -nostdlib freestanding).
            //   Imprimir algo como:
            //     "[C0] ventana cerrada: <errores> errores / <bits> bits"
            //     "  -> BER ~= <ppm> ppm  (SW=<sw_read()>)"
            //   usando uart_puts()/uart_print_uint().
            //   Después: reiniciar window_blocks y window_errors a 0.
            // ---------------------------------------------------------
            ppm = (uint32_t)(((uint64_t)window_errors * 1000000ULL) / WINDOW_BITS);

            uart_puts("[C0] Errores: ");
            uart_print_uint(window_errors);
            uart_puts(" Bits: ");
            uart_print_uint(WINDOW_BITS);
            uart_puts(" BER: ");
            uart_print_uint(ppm);
            uart_puts(" ppm\r\n");

            window_blocks = 0;
            window_errors = 0;
        }

        delay_cycles(DELAY_CYCLES);
    }
}

// =============================================================================
// app_prbs.c — Aplicación de Core 1 cargada por el bootloader (Jornada 5)
//
// Core 1 en soc_boot.v no tiene UART ni mailbox -- solo GPIO (LEDs). Esta
// variante genera un stream PRBS-15, le inyecta errores a una tasa fija, y
// lo verifica con el mismo checker autosincronizante de las Jornadas 4 y 5
// (generador y checker corren los dos dentro de Core 1, en loopback local:
// no hay Core 0 del otro lado en este lab -- el objetivo de esta jornada es
// el mecanismo de recarga de firmware, no repetir la medición cruzada).
//
// El BER de cada ventana se muestra como "barras" de LEDs:
//   BER == 0 ppm         -> 0001
//   0 < BER <= 1000 ppm  -> 0011
//   1000 < BER <= 5000   -> 0111
//   BER > 5000 ppm       -> 1111
//
// Ver app_prbs_alt.c: mismo firmware con otra tasa de inyección de errores,
// para demostrar que recargar en caliente cambia el BER medido sin
// resintetizar el bitstream.
// =============================================================================

#include <stdint.h>
#include "prbs.h"

#define GPIO (*(volatile uint32_t*)0x300000)

#ifndef ERR_PERIOD_BITS
#define ERR_PERIOD_BITS 1021u   /* primo; 0 = sin errores */
#endif

#define WINDOW_WORDS 32u   /* 1024 bits por ventana, igual que Jornada 4/5 */

static inline uint32_t rdcycle(void) {
    uint32_t v;
    asm volatile("rdcycle %0" : "=r"(v));
    return v;
}

static void delay(uint32_t ciclos) {
    uint32_t t0 = rdcycle();
    while ((rdcycle() - t0) < ciclos);
}

static uint32_t gen_word_with_errors(prbs_gen_t *g, uint32_t *bit_count) {
    uint32_t w = 0;
    for (int i = 0; i < 32; i++) {
        uint32_t bit = prbs_gen_bit(g);
        (*bit_count)++;
        if (ERR_PERIOD_BITS && (*bit_count % ERR_PERIOD_BITS) == 0)
            bit ^= 1u;
        w |= bit << i;
    }
    return w;
}

void main(void) {
    GPIO = 0x4;   // LED[2]: Core 1 arrancó (igual que app_led.c)

    prbs_gen_t gen;
    prbs_chk_t chk;
    prbs_gen_init(&gen, 0x1ACEu);
    prbs_chk_init(&chk, 0x0001u);
    uint32_t bit_count = 0;

    while (1) {
        uint32_t window_errors = 0;
        for (uint32_t i = 0; i < WINDOW_WORDS; i++) {
            uint32_t w = gen_word_with_errors(&gen, &bit_count);
            window_errors += prbs_chk_word(&chk, w);
        }
        uint32_t ppm = (window_errors * 1000000u) / (WINDOW_WORDS * 32u);

        uint32_t leds;
        if (ppm == 0)        leds = 0x1;
        else if (ppm <= 1000) leds = 0x3;
        else if (ppm <= 5000) leds = 0x7;
        else                  leds = 0xF;

        GPIO = leds;
        delay(5000000);   // ~50 ms a 100 MHz, para que sea visible
    }
}

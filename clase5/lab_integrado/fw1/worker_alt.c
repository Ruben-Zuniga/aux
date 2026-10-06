// =============================================================================
// worker_alt.c — Variante de worker.c con OTRO polinomio de checker
// Jornada extra — recarga en caliente de Core 1 (mailbox + bootloader)
//
// Mismo mailbox, mismo protocolo IDLE/WORK/DONE que worker.c -- lo único que
// cambia es el polinomio con el que el checker predice el próximo bit.
// worker.c usa el mismo polinomio que el generador de Core 0 (prbs.h,
// x^15+x^14+1, taps 14/13) y por eso mide el BER real inyectado por SW.
//
// Esta variante usa x^15+x^13+1 (taps 14/12) -- UN POLINOMIO DISTINTO al del
// generador. El checker nunca converge con el stream que recibe (no es un
// error de transmisión lo que ve, es una PREDICCIÓN equivocada en cada bit),
// así que reporta un BER alto y estable en vez del BER real de los switches.
//
// Sirve como demo de que la recarga en caliente cambió el firmware que
// corre en Core 1 de verdad: cargar esta variante con
//   host/loader.py --bin fw1/worker_alt.bin
// mientras el mailbox ya está funcionando (ver Makefile: make reload-alt)
// hace que el BER reportado por Core 0 salte de forma visible en la consola,
// sin resintetizar y sin tocar Core 0 (idea documentada en
// comun/DISENO_PRBS_BER.txt, punto 6, para la Jornada 6 original).
// =============================================================================

#include <stdint.h>
#include "mailbox_prbs.h"
#include "prbs.h"

#define ALT_MASK 0x7FFFu

typedef struct { uint32_t reg; } alt_chk_t;

static inline void alt_chk_init(alt_chk_t *c, uint32_t seed) {
    c->reg = seed & ALT_MASK;
    if (c->reg == 0) c->reg = 1;
}

// Taps 14/12 (x^15 + x^13 + 1) en vez de los 14/13 (x^15 + x^14 + 1) de
// prbs.h -- a propósito distinto, documentado acá mismo.
static inline uint32_t alt_chk_bit(alt_chk_t *c, uint32_t rx_bit) {
    uint32_t predicted = ((c->reg >> 14) ^ (c->reg >> 12)) & 1u;
    uint32_t err = predicted ^ (rx_bit & 1u);
    c->reg = ((c->reg << 1) | (rx_bit & 1u)) & ALT_MASK;
    return err;
}

static inline uint32_t alt_chk_word(alt_chk_t *c, uint32_t w) {
    uint32_t errs = 0;
    for (int i = 0; i < 32; i++)
        errs += alt_chk_bit(c, (w >> i) & 1u);
    return errs;
}

void main(void) {
    alt_chk_t chk;
    alt_chk_init(&chk, 0x0001u);

    while (1) {
        while (MBX_STATE != MBX_WORK);

        uint32_t block_errors = 0;
        for (uint32_t i = 0; i < BLOCK_WORDS; i++)
            block_errors += alt_chk_word(&chk, MBX_DATA[i]);

        MBX_ERRORS = block_errors;
        MBX_STATE  = MBX_DONE;
    }
}

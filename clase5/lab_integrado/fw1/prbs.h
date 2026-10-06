// =============================================================================
// prbs.h — PRBS-15 (ITU-T O.150: x^15 + x^14 + 1) generador + checker
//          autosincronizante, compartido por Jornadas 4, 5 y 6 del curso.
//
// El checker NO recibe la semilla del generador: se autosincroniza cargando
// su propio registro con los bits RECIBIDOS (no con la realimentación
// interna). Es la misma técnica que usa un BERT real (ITU-T O.150/O.151):
// tras ~15 bits correctos el checker predice igual que el generador. Un
// error de transmisión aparece multiplicado (factor = cantidad de taps = 2)
// durante las siguientes 15 comparaciones y luego el checker resincroniza
// solo, sin intervención de software.
// =============================================================================

#ifndef PRBS_H
#define PRBS_H

#include <stdint.h>

#define PRBS_MASK 0x7FFFu   /* registro de 15 bits */

typedef struct { uint32_t reg; } prbs_gen_t;
typedef struct { uint32_t reg; } prbs_chk_t;

static inline void prbs_gen_init(prbs_gen_t *g, uint32_t seed) {
    g->reg = seed & PRBS_MASK;
    if (g->reg == 0) g->reg = 1;   /* la semilla 0 nunca produce salida */
}

/* Genera un bit y avanza el LFSR. La salida ES el bit de realimentación. */
static inline uint32_t prbs_gen_bit(prbs_gen_t *g) {
    uint32_t fb = ((g->reg >> 14) ^ (g->reg >> 13)) & 1u;
    g->reg = ((g->reg << 1) | fb) & PRBS_MASK;
    return fb;
}

/* Empaqueta 32 bits generados en una palabra (bit 0 = primer bit generado). */
static inline uint32_t prbs_gen_word(prbs_gen_t *g) {
    uint32_t w = 0;
    for (int i = 0; i < 32; i++)
        w |= prbs_gen_bit(g) << i;
    return w;
}

static inline void prbs_chk_init(prbs_chk_t *c, uint32_t seed) {
    c->reg = seed & PRBS_MASK;
    if (c->reg == 0) c->reg = 1;
}

/* Predice el próximo bit ANTES de conocerlo, compara contra el recibido,
 * y recién después desplaza el bit recibido hacia adentro (autosync). */
static inline uint32_t prbs_chk_bit(prbs_chk_t *c, uint32_t rx_bit) {
    uint32_t predicted = ((c->reg >> 14) ^ (c->reg >> 13)) & 1u;
    uint32_t err = predicted ^ (rx_bit & 1u);
    c->reg = ((c->reg << 1) | (rx_bit & 1u)) & PRBS_MASK;
    return err;
}

/* Procesa una palabra recibida (mismo orden de bits que prbs_gen_word) y
 * devuelve la cantidad de bits que no coincidieron con la predicción. */
static inline uint32_t prbs_chk_word(prbs_chk_t *c, uint32_t w) {
    uint32_t errs = 0;
    for (int i = 0; i < 32; i++)
        errs += prbs_chk_bit(c, (w >> i) & 1u);
    return errs;
}

#endif /* PRBS_H */

// =============================================================================
// sw.h — Driver de los switches SW[3:0] de la Arty A7 (Jornada 4)
//
// Mapeados como GPIO de entrada en 0x200004 (offset dentro de la región
// GPIO 0x200000, ver soc_2core.v). Seleccionan en vivo, sin recompilar,
// uno de 16 niveles de inyección de error del stream PRBS.
// =============================================================================
#ifndef SW_H
#define SW_H

#include <stdint.h>

#define GPIO_SW (*(volatile uint32_t *)0x00200004)

static inline uint32_t sw_read(void) {
    return GPIO_SW & 0xFu;
}

// Periodo de inyección (en bits) por nivel de SW[3:0]. Nivel 0 = sin
// errores. Valores impares/primos para no alinear con el empaquetado
// de 32 bits por palabra (mismo criterio que el ERR_PERIOD_BITS original).
static const uint32_t ERR_PERIOD_TABLE[16] = {
    0,                                  /* 0000: sin errores        */
    100003, 50021, 25013, 16001,        /* 0001..0100: BER bajo     */
    8009,   4001,  2003,  1021,         /* 0101..1000: BER medio    */
    509,    251,   127,   61,           /* 1001..1100: BER alto     */
    31,     17,    7                    /* 1101..1111: BER muy alto */
};

static inline uint32_t sw_err_period(void) {
    return ERR_PERIOD_TABLE[sw_read()];
}

#endif /* SW_H */

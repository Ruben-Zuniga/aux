// =============================================================================
// worker.c — Firmware Core 1: checker PRBS autosincronizante (Jornada 4)
//
// Core 1 espera un bloque en el mailbox, lo chequea bit a bit contra su
// propia predicción PRBS-15 (sin conocer la semilla de Core 0 — se
// autosincroniza con los bits recibidos, ver funda/comun/DISENO_PRBS_BER.txt),
// y devuelve la cantidad de bits que no coincidieron con la predicción.
// No tiene UART ni GPIO — el mailbox es su único canal de comunicación.
// =============================================================================

#include <stdint.h>
#include "mailbox_prbs.h"
#include "prbs.h"

void main(void) {
    prbs_chk_t chk;
    prbs_chk_init(&chk, 0x0001u);

    while (1) {
        // Esperar un bloque nuevo de Core 0
        while (MBX_STATE != MBX_WORK);

        uint32_t block_errors = 0;
        for (uint32_t i = 0; i < BLOCK_WORDS; i++)
            block_errors += prbs_chk_word(&chk, MBX_DATA[i]);

        // Escribir resultado y señalizar que está listo
        MBX_ERRORS = block_errors;
        MBX_STATE  = MBX_DONE;
    }
}

// =============================================================================
// mailbox_prbs.h — Protocolo de mailbox por BLOQUES para PRBS/BER (Jornada 4)
//
// Mapa de la BRAM compartida (base = 0x00500000):
//   +0x00                    MBX_STATE   IDLE=0 / WORK=1 / DONE=2
//   +0x04 .. +0x04+4*32-1    MBX_DATA[32]  32 palabras = 1024 bits de PRBS
//   +0x84                    MBX_ERRORS  bits erroneos detectados en el bloque
//
// Protocolo (igual al de la Jornada anterior, solo cambia el contenido):
//   Core 0: genera el bloque en MBX_DATA, pone STATE = MBX_WORK
//   Core 1: detecta WORK, chequea el bloque, escribe MBX_ERRORS, pone STATE = MBX_DONE
//   Core 0: detecta DONE, lee MBX_ERRORS, acumula, pone STATE = MBX_IDLE
// =============================================================================

#ifndef MAILBOX_PRBS_H
#define MAILBOX_PRBS_H

#include <stdint.h>

// ---------------------------------------------------------------------------
// TODO 1: Definir MBX_BASE con la dirección base 0x00500000
//   El mailbox está mapeado en 0x500000-0x5000FF (ver mapa de memoria en soc_2core.v)
// ---------------------------------------------------------------------------
#define MBX_BASE       0x00500000UL
#define BLOCK_WORDS    32u                 /* 1024 bits por bloque */

// ---------------------------------------------------------------------------
// TODO 2: Definir MBX_STATE, MBX_DATA y MBX_ERRORS como punteros volatiles
//   Patron: (*(volatile uint32_t *)(MBX_BASE + offset))  para un registro
//           ((volatile uint32_t *)(MBX_BASE + offset))   para un arreglo
//   MBX_STATE  -> offset 0x00
//   MBX_DATA   -> offset 0x04           (arreglo de BLOCK_WORDS palabras)
//   MBX_ERRORS -> offset 0x?? (despues de las BLOCK_WORDS palabras de datos)
// ---------------------------------------------------------------------------
#define MBX_STATE      (*(volatile uint32_t *)(MBX_BASE + 0x00))
#define MBX_DATA       ( (volatile uint32_t *)(MBX_BASE + 0x04))
#define MBX_ERRORS     (*(volatile uint32_t *)(MBX_BASE + 0x84))

// ---------------------------------------------------------------------------
// TODO 3: Definir los estados del protocolo (mismos nombres que ya conoces)
//   MBX_IDLE = 0  (mailbox libre — ya esta dado)
//   MBX_WORK = ?u (Core 0 cargo un bloque; Core 1 debe procesarlo)
//   MBX_DONE = ?u (Core 1 escribio MBX_ERRORS; Core 0 puede leerlo)
// ---------------------------------------------------------------------------
#define MBX_IDLE   0u
#define MBX_WORK   1u
#define MBX_DONE   2u

/* Cuantos bloques componen una "ventana" de medicion de BER */
#define WINDOW_BLOCKS  8u
#define WINDOW_BITS    (WINDOW_BLOCKS * BLOCK_WORDS * 32u)

#endif /* MAILBOX_PRBS_H */

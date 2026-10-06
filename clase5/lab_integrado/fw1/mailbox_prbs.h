// =============================================================================
// mailbox_prbs.h — Protocolo de mailbox por BLOQUES para el caso de aplicación
//                  PRBS/BER (Jornadas 4, 5 y 6).
//
// Reutiliza tal cual el RTL de mailbox introducido en esta misma Jornada (BRAM TDP de
// 64 palabras = 256 bytes, protocolo de 3 fases IDLE/WORK/DONE) — no se
// modifica ningún .v. Lo único que cambia respecto del demo de "suma" de
// fábrica es qué va adentro del mailbox: en vez de un único operando, Core 0
// escribe un BLOQUE de BLOCK_WORDS palabras de stream PRBS (con errores ya
// inyectados) y Core 1 devuelve, en un único resultado, la cantidad de bits
// que detectó mal en ese bloque.
//
// Mapa de la BRAM compartida (base = 0x00500000):
//   +0x00                    MBX_STATE   IDLE=0 / WORK=1 / DONE=2
//   +0x04 .. +0x04+4*32-1    MBX_DATA[32]  32 palabras = 1024 bits de PRBS
//   +0x84                    MBX_ERRORS  bits erróneos detectados en el bloque
//   (total: 1 + 32 + 1 = 34 palabras de 64 disponibles — sobra margen)
//
// Protocolo (idéntico al ya usado, solo cambia el contenido):
//   Core 0: genera el bloque en MBX_DATA, pone STATE = MBX_WORK
//   Core 1: detecta WORK, chequea el bloque con prbs_chk_word(), escribe
//           MBX_ERRORS, pone STATE = MBX_DONE
//   Core 0: detecta DONE, lee MBX_ERRORS, acumula, pone STATE = MBX_IDLE
// =============================================================================

#ifndef MAILBOX_PRBS_H
#define MAILBOX_PRBS_H

#include <stdint.h>

#define MBX_BASE       0x00500000UL
#define BLOCK_WORDS    32u                 /* 1024 bits por bloque */

#define MBX_STATE      (*(volatile uint32_t *)(MBX_BASE + 0x00))
#define MBX_DATA       ((volatile uint32_t *)(MBX_BASE + 0x04))
#define MBX_ERRORS     (*(volatile uint32_t *)(MBX_BASE + 0x04 + 4*BLOCK_WORDS))

#define MBX_IDLE   0u   /* mailbox libre — Core 0 puede enviar un bloque nuevo */
#define MBX_WORK   1u   /* Core 0 puso un bloque — Core 1 debe procesarlo */
#define MBX_DONE   2u   /* Core 1 puso MBX_ERRORS — Core 0 puede leerlo */

/* Cuántos bloques componen una "ventana" de medición de BER (Jornada 4/5) */
#define WINDOW_BLOCKS  8u
#define WINDOW_BITS    (WINDOW_BLOCKS * BLOCK_WORDS * 32u)

#endif /* MAILBOX_PRBS_H */

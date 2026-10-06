/* =============================================================================
 * start.S — CRT0 mínimo para PicoRV32
 * Jornada extra — mailbox + bootloader
 *
 * Este archivo corre ANTES de main().
 * PicoRV32 salta a dirección 0x000000 en el reset (PROGADDR_RESET).
 *
 * Responsabilidades:
 *   1. Inicializar el stack pointer (sp) al tope de la BRAM
 *   2. Limpiar la sección .bss (variables globales sin inicializar)
 *   3. Llamar a main()
 *   4. Loop infinito si main() retorna
 * ============================================================================= */

.section .text.start   /* la sección .text.start se linkea PRIMERO (ver link.ld) */
.global _start

_start:
    /* ---- 1. Inicializar stack pointer ---- */
    la   sp, _stack_top          /* sp = 0x4000 (tope de BRAM, del linker script) */

    /* ---- 2. Limpiar .bss ---- */
    la   a0, _bss_start
    la   a1, _bss_end
_bss_loop:
    bgeu a0, a1, _bss_done       /* si a0 >= a1: terminamos */
    sw   zero, 0(a0)             /* MEM[a0] = 0 */
    addi a0, a0, 4               /* a0 += 4 (avanza una palabra) */
    j    _bss_loop
_bss_done:

    /* ---- 3. Llamar a main ---- */
    call main

    /* ---- 4. Loop infinito (main nunca debería retornar) ---- */
_halt:
    j _halt

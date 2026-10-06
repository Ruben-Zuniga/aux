/* =============================================================================
 * start.S — CRT0 mínimo para PicoRV32
 * Lab 3b — Clase 3
 *
 * Responsabilidades:
 *   1. Inicializar el stack pointer
 *   2. Limpiar la sección .bss
 *   3. Llamar a main()
 *   4. Loop infinito si main retorna (nunca debería)
 * ============================================================================= */

.section .text
.global _start

_start:
    /* Inicializar stack pointer al valor definido en el linker script */
    la   sp, _stack_top

    /* Limpiar .bss (variables globales no inicializadas) */
    la   a0, _bss_start
    la   a1, _bss_end
_bss_loop:
    bgeu a0, a1, _bss_done
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    _bss_loop
_bss_done:

    /* Llamar a main */
    call main

    /* Si main retorna: loop infinito */
_halt:
    j _halt

/* =============================================================================
 * link.ld — Linker script para PicoRV32 + BRAM
 * Lab 3b — Clase 3
 *
 * Mapa de memoria del soc_minimal:
 *   0x000000 – 0x003FFF  BRAM (16 KB = 16384 bytes)
 *   Stack al final de la BRAM (crece hacia abajo)
 *
 * Nota: región única BRAM → LMA == VMA para .data/.sdata.
 *   start.S no necesita copiar inicializados desde flash.
 * ============================================================================= */

MEMORY {
    BRAM (rwx) : ORIGIN = 0x000000, LENGTH = 16K
}

SECTIONS {
    /* Instrucciones y datos de solo lectura */
    .text : {
        *(.text.start)      /* _start primero */
        *(.text*)
        *(.rodata*)
    } > BRAM

    /* Variables globales inicializadas (incluye .sdata de GCC) */
    .data : {
        _data_start = .;
        *(.data*) *(.sdata*)
        _data_end = .;
    } > BRAM

    /* Variables globales no inicializadas (limpiadas en _start) */
    .bss : {
        _bss_start = .;
        *(.bss*) *(.sbss*)
        *(COMMON)
        _bss_end = .;
    } > BRAM

    /* Puntero de stack (al final de BRAM, crece hacia abajo) */
    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);

    /* Símbolo para medir tamaño del firmware */
    _firmware_end = .;
}

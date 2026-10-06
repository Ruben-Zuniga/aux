/* =============================================================================
 * link.ld — Linker script para PicoRV32 + BRAM
 * Jornada extra — mailbox + bootloader
 *
 * Mapa de memoria del soc_minimal:
 *   0x000000 – 0x003FFF  BRAM (16 KB = 4096 palabras de 32 bits)
 *   0x200000             GPIO (periférico externo a la BRAM)
 *
 * La BRAM contiene todo: código, datos de solo lectura, datos inicializados
 * y datos no inicializados (.bss). Stack crece hacia abajo desde el final.
 * ============================================================================= */

MEMORY {
    BRAM (rwx) : ORIGIN = 0x000000, LENGTH = 16K
}

SECTIONS {
    .text : {
        *(.text.start)      /* _start siempre al principio (dirección 0x000000) */
        *(.text*)
        *(.rodata*)
    } > BRAM

    .data : {
        _data_start = .;
        *(.data*) *(.sdata*)
        _data_end = .;
    } > BRAM

    .bss : {
        _bss_start = .;
        *(.bss*) *(.sbss*)
        *(COMMON)
        _bss_end = .;
    } > BRAM

    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);  /* 0x4000 */
    _firmware_end = .;
}

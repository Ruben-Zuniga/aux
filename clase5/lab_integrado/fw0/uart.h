// =============================================================================
// uart.h — Driver bare-metal para uart_regs.v
// Jornada extra — UART (reutilizado de la Jornada 2)
//
// Mapa de registros (base = 0x00300000):
//   +0x00  DATA   — W: byte a transmitir  /  R: byte recibido (limpia RX_VALID)
//   +0x04  STATUS — bit0=TX_BUSY  bit1=RX_VALID  bit2=RX_OVERFLOW
// =============================================================================

#ifndef UART_H
#define UART_H

#include <stdint.h>

#ifndef UART_BASE
#define UART_BASE  0x00300000UL
#endif

#define UART_DATA    (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_STATUS  (*(volatile uint32_t *)(UART_BASE + 0x04))

#define UART_TX_BUSY     (1u << 0)
#define UART_RX_VALID    (1u << 1)
#define UART_RX_OVERFLOW (1u << 2)

static inline void uart_putc(char c)
{
    while (UART_STATUS & UART_TX_BUSY)
        ;
    UART_DATA = (uint32_t)(uint8_t)c;
}

static inline void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

static inline int uart_rx_ready(void)
{
    return (UART_STATUS & UART_RX_VALID) != 0;
}

static inline char uart_getc(void)
{
    while (!uart_rx_ready())
        ;
    return (char)(UART_DATA & 0xFF);
}

static inline int uart_readline(char *buf, int max_len)
{
    int n = 0;
    while (n < max_len - 1) {
        char c = uart_getc();
        if (c == '\r' || c == '\n')
            break;
        buf[n++] = c;
        uart_putc(c);   // eco local
    }
    buf[n] = '\0';
    return n;
}

static inline void uart_print_uint(uint32_t v)
{
    char tmp[11];
    int  i = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) { tmp[i++] = '0' + (v % 10); v /= 10; }
    while (i--) uart_putc(tmp[i]);
}

static inline void uart_print_hex(uint32_t v)
{
    const char hex[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(hex[(v >> i) & 0xF]);
}

#endif /* UART_H */

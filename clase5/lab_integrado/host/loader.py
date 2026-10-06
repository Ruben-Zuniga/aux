#!/usr/bin/env python3
"""
loader.py — Cargador de firmware para SoC PicoRV32 con Bootloader
Jornada 5 — Bootloader PRBS/BER

Protocolo (igual que boot.c):
  1. Enviar sincronización AA 55, esperar ACK (0x06)
  2. Enviar 4 bytes de tamaño (little-endian)
  3. Para cada chunk de 64 bytes:
       a. Enviar 64 bytes de datos
       b. Enviar 1 byte de checksum XOR del chunk
       c. Recibir ACK (0x06) o NACK (0x15)
       d. Si NACK: reenviar el MISMO chunk (hasta MAX_RETRIES veces)

Uso:
  python3 loader.py --port /dev/ttyUSB1 --bin fw/app.bin
  python3 loader.py --port /dev/ttyUSB1 --bin fw/app.bin --monitor
"""

import serial
import sys
import time
import argparse

ACK          = 0x06
NACK         = 0x15
SYNC         = bytes([0xAA, 0x55])
CHUNK_SIZE   = 64
MAX_RETRIES  = 5


def wait_sync_ack(ser: serial.Serial) -> bool:
    ser.write(SYNC)
    ser.flush()
    # Core 0 puede estar en medio de un print de estado (p.ej. el reporte
    # periódico de BER del manager de mailbox) cuando llega el sync -- no
    # lo atiende hasta terminar de transmitirlo, así que puede llegar acá
    # ANTES algún byte de ese texto (p.ej. el '\r' final), no el ACK real.
    # Ignorar cualquier byte que no sea ACK y seguir esperando dentro del
    # mismo timeout: el sync queda latcheado del lado de la FPGA (no tiene
    # FIFO, pero un solo byte pendiente no se pierde) y el ACK real llega
    # apenas Core 0 termina el print y atiende la UART.
    deadline = time.time() + ser.timeout
    while time.time() < deadline:
        resp = ser.read(1)
        if not resp:
            break
        if resp[0] == ACK:
            return True
    print("[ERROR] Timeout esperando ACK de sincronización")
    return False


def load_firmware(ser: serial.Serial, firmware: bytes) -> bool:
    size = len(firmware)
    if size == 0 or size > 16 * 1024:
        print(f"[ERROR] Tamaño inválido: {size} bytes (máximo 16 KB)")
        return False

    if not wait_sync_ack(ser):
        return False

    n_chunks = (size + CHUNK_SIZE - 1) // CHUNK_SIZE
    print(f"[LOAD] {size} bytes — {n_chunks} chunks de {CHUNK_SIZE} bytes")

    # Enviar tamaño (4 bytes little-endian)
    size_bytes = size.to_bytes(4, 'little')
    ser.write(size_bytes)
    ser.flush()

    # Enviar chunks
    offset = 0
    for c in range(n_chunks):
        chunk = firmware[offset : offset + CHUNK_SIZE]
        # Rellenar el último chunk con ceros si es corto
        if len(chunk) < CHUNK_SIZE:
            chunk = chunk + b'\x00' * (CHUNK_SIZE - len(chunk))

        xor_sum = 0
        for b in chunk:
            xor_sum ^= b

        for attempt in range(MAX_RETRIES):
            ser.write(chunk)
            ser.write(bytes([xor_sum]))
            ser.flush()

            resp = ser.read(1)
            if not resp:
                print(f"[ERROR] Timeout esperando ACK/NACK para chunk {c}")
                return False
            if resp[0] == ACK:
                break
            if resp[0] == NACK:
                print(f"\n[WARN] NACK en chunk {c} (intento {attempt+1}/{MAX_RETRIES}) "
                      f"— reintentando")
                continue
            print(f"[ERROR] Respuesta inesperada en chunk {c}: 0x{resp[0]:02X}")
            return False
        else:
            print(f"[ERROR] Chunk {c}: se agotaron los {MAX_RETRIES} reintentos")
            return False

        offset += CHUNK_SIZE
        pct = min((offset * 100) // size, 100)
        bar = '=' * (pct // 5) + '>' + ' ' * (20 - pct // 5)
        print(f"\r  [{bar}] {pct:3d}% ({min(offset,size)}/{size} bytes)", end='', flush=True)

    print()
    print(f"[LOAD] Firmware cargado exitosamente en Core 1")
    return True


def monitor(ser: serial.Serial):
    print("[MONITOR] Conectado. Ctrl+C para salir.")
    buf = b""
    while True:
        try:
            data = ser.read(256)
            if data:
                buf += data
                while b'\n' in buf:
                    idx  = buf.index(b'\n')
                    line = buf[:idx].decode('ascii', errors='replace').rstrip('\r')
                    buf  = buf[idx+1:]
                    print(line)
        except KeyboardInterrupt:
            print("\n[MONITOR] Saliendo.")
            break


def main():
    parser = argparse.ArgumentParser(
        description='Cargador de firmware para SoC PicoRV32 — Jornada 5')
    parser.add_argument('--port',    required=True,
                        help='Puerto serie (ej: /dev/ttyUSB1, COM3)')
    parser.add_argument('--baud',    type=int, default=115200)
    parser.add_argument('--bin',     required=True,
                        help='Archivo .bin a cargar en Core 1')
    parser.add_argument('--monitor', action='store_true',
                        help='Entrar en modo monitor tras la carga')
    parser.add_argument('--timeout', type=float, default=5.0,
                        help='Timeout de respuesta en segundos')
    args = parser.parse_args()

    with open(args.bin, 'rb') as f:
        firmware = f.read()
    print(f"[LOAD] Firmware: {args.bin} ({len(firmware)} bytes)")

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        time.sleep(0.1)
        ser.reset_input_buffer()

        # Imprimir cualquier mensaje inicial del bootloader -- OJO: nunca
        # "ser.read(ser.in_waiting or 1)". Si todavía no llegó nada
        # (in_waiting == 0), ese "or 1" fuerza una lectura BLOQUEANTE de 1
        # byte con el timeout completo del puerto (5 s por defecto) ANTES
        # de mandar el sync -- eso le come al firmware su propia ventana de
        # TIMEOUT_CYCLES (~5 s) sin haber llegado siquiera a escribir AA 55,
        # y el bootloader se rinde solo. Leer únicamente lo que ya está
        # bufferizado evita bloquear acá.
        time.sleep(0.5)
        pending = ser.read(ser.in_waiting) if ser.in_waiting else b''
        if pending:
            print(pending.decode('ascii', errors='replace'), end='')

        ok = load_firmware(ser, firmware)
        if not ok:
            sys.exit(1)

        if args.monitor:
            monitor(ser)


if __name__ == '__main__':
    main()

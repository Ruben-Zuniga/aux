#!/usr/bin/env python3
# bin2hex.py — Convierte boot.bin a formato $readmemh (palabras de 32 bits, little-endian)
# Uso: python3 bin2hex.py boot.bin > boot.hex

import sys
import struct

if len(sys.argv) < 2:
    print("Uso: bin2hex.py <archivo.bin>", file=sys.stderr)
    sys.exit(1)

BRAM_DEPTH = 4096   # palabras de 32 bits (MEM_WORDS en soc_minimal)

data = open(sys.argv[1], 'rb').read()

# Padding a múltiplo de 4 bytes
while len(data) % 4:
    data += b'\x00'

words = []
for i in range(0, len(data), 4):
    word, = struct.unpack_from('<I', data, i)
    words.append(word)

# Rellenar hasta BRAM_DEPTH con ceros
while len(words) < BRAM_DEPTH:
    words.append(0)

for w in words:
    print(f'{w:08x}')

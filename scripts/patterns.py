"""Generate small, lossless display patterns with only Python's standard library."""
import os
import struct
import sys
import zlib


def png(path, width, height, pixel):
    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    data = bytearray()
    for y in range(height):
        data.append(0)
        for x in range(width):
            data.extend(pixel(x, y))
    with open(path, "wb") as stream:
        stream.write(b"\x89PNG\r\n\x1a\n")
        stream.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        stream.write(chunk(b"IDAT", zlib.compress(data, 6)))
        stream.write(chunk(b"IEND", b""))


destination = sys.argv[1]
for name, rgb in [("black", (0, 0, 0)), ("white", (255, 255, 255)),
                  ("red", (255, 0, 0)), ("green", (0, 255, 0)),
                  ("blue", (0, 0, 255)), ("gray", (128, 128, 128))]:
    png(os.path.join(destination, name + ".png"), 640, 400, lambda _x, _y, color=rgb: color)
png(os.path.join(destination, "gradient.png"), 640, 400,
    lambda x, _y: (round(255 * x / 639),) * 3)

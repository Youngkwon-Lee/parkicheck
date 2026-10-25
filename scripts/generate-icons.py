"""Reproducible, dependency-free ParkiCheck PWA icon generator."""
from pathlib import Path
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "icons"


def png_chunk(kind, data):
    payload = kind + data
    return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)


def image(size):
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            u = (x + 0.5) / size
            v = (y + 0.5) / size
            # Teal "P" movement mark on an opaque, dark square.
            pixel = [int(6 + 9 * (1 - v)), int(11 + 12 * u), int(26 + 16 * (1 - u))]
            dx = u - .5
            dy = v - .5
            r = math.hypot(dx, dy)
            ring = abs(r - .31) < .018
            glow = max(0, 1 - abs(r - .31) / .095)
            for i, tint in enumerate((0, 108, 94)):
                pixel[i] = min(255, int(pixel[i] + tint * glow * .25))
            if ring:
                pixel = [0, 230, 190]
            # Rounded stem + bowl: recognizable P even at small icon sizes.
            stem = (.398 <= u <= .44 and .334 <= v <= .706)
            bowl_r = math.hypot((u - .474) / .128, (v - .415) / .116)
            bowl_inner = math.hypot((u - .474) / .082, (v - .415) / .064)
            bowl = (bowl_r <= 1 and bowl_inner >= 1 and u >= .416)
            dot = (u - .625) ** 2 + (v - .665) ** 2 < .021 ** 2
            if stem or bowl:
                pixel = [242, 252, 255]
            if dot:
                pixel = [0, 232, 192]
            row.extend((*pixel, 255))
        rows.append(b"\x00" + bytes(row))
    raw = b"".join(rows)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(raw, level=9))
        + png_chunk(b"IEND", b"")
    )


def main():
    OUT.mkdir(exist_ok=True)
    for name, size in (("icon-192.png", 192), ("icon-512.png", 512), ("icon-1024.png", 1024), ("apple-touch-icon.png", 180)):
        target = OUT / name
        target.write_bytes(image(size))
        print(str(target) + " (" + str(target.stat().st_size) + " bytes)")


if __name__ == "__main__":
    main()

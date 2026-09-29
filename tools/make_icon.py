#!/usr/bin/env python3
"""Genera los PNG del icono de Slay (chulito naranja estilo terminal).

Rasterización analítica del polyline con supersampling 3x3 para
antialiasing suave, escrita directamente a PNG (RGB 8-bit) sin
dependencias externas.
"""
import math
import struct
import zlib

SIZE = 1024

# ── Paleta del tema terminal ─────────────────────────────────
BG = (0x17, 0x11, 0x0D)      # marrón muy oscuro (noche)
ORANGE = (0xFC, 0x78, 0x4B)  # acento naranja (noche)
WHITE = (0xFF, 0xFF, 0xFF)

# Polylines del chulito (icono completo y foreground con safe zone).
FULL_PTS = [(265, 545), (445, 720), (765, 335)]
FULL_W = 125
FG_PTS = [(325, 535), (460, 665), (705, 375)]
FG_W = 95
MONO_PTS = FULL_PTS
MONO_W = FULL_W


def dist_to_segment(px, py, ax, ay, bx, by):
    """Distancia de punto a segmento. Para (ax,ay)==(bx,by) usa el punto."""
    dx, dy = bx - ax, by - ay
    len2 = dx * dx + dy * dy
    if len2 == 0.0:
        return math.hypot(px - ax, py - ay)
    t = ((px - ax) * dx + (py - ay) * dy) / len2
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def dist_to_polyline(px, py, pts):
    if not pts:
        return float("inf")
    return min(
        dist_to_segment(px, py, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1])
        for i in range(len(pts) - 1)
    )


def coverage(px, py, half_w, pts, ss=3):
    """Fracción de cobertura 0..1 del trazo en un pixel, con supersampling."""
    step = 1.0 / ss
    hit = 0
    for sy in range(ss):
        for sx in range(ss):
            x = px + (sx + 0.5) * step
            y = py + (sy + 0.5) * step
            if dist_to_polyline(x, y, pts) <= half_w:
                hit += 1
    return hit / (ss * ss)


def blend(base, over, alpha):
    return tuple(
        int(round(over[c] * alpha + base[c] * (1.0 - alpha)))
        for c in range(3)
    )


def write_png(path, size, pixel_fn):
    """Escribe un PNG RGB 8-bit sin filtros, con zlib."""
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filtro 0
        for x in range(size):
            raw.extend(pixel_fn(x, y))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print(f"OK  {path}")


def make_flat(path, size, pts, width):
    half = width / 2.0
    scale = size / SIZE

    def px(x, y):
        # Coordenadas de layout -> pixel con escala.
        fx, fy = (x + 0.5) / scale, (y + 0.5) / scale
        cov = coverage(fx, fy, half, pts)
        return blend(BG, ORANGE, cov)

    write_png(path, size, px)


def make_monochrome(path, size, pts, width):
    half = width / 2.0
    scale = size / SIZE

    def px(x, y):
        fx, fy = (x + 0.5) / scale, (y + 0.5) / scale
        cov = coverage(fx, fy, half, pts)
        return blend((0, 0, 0), WHITE, cov)

    write_png(path, size, px)


def make_foreground(path, size, pts, width):
    """Foreground del adaptive icon: trazo sobre transparente (RGBA)."""
    half = width / 2.0
    scale = size / SIZE

    def px(x, y):
        fx, fy = (x + 0.5) / scale, (y + 0.5) / scale
        cov = coverage(fx, fy, half, pts)
        return (ORANGE[0], ORANGE[1], ORANGE[2], int(round(cov * 255)))

    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            raw.extend(px(x, y))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print(f"OK  {path}")


if __name__ == "__main__":
    import os
    os.makedirs("assets/icon", exist_ok=True)

    # Ícono completo para todas las densidades.
    make_flat("assets/icon/icon_1024.png", 1024, FULL_PTS, FULL_W)
    # Foreground adaptive (con transparencia) + fondo como PNG aparte.
    make_foreground("assets/icon/icon_foreground.png", 1024, FG_PTS, FG_W)
    make_flat("assets/icon/icon_background.png", 1024, [], 0)
    # Monochrome (Android 13+ themed icons).
    make_monochrome("assets/icon/icon_monochrome.png", 1024, FULL_PTS, FULL_W)
    print("Listo.")

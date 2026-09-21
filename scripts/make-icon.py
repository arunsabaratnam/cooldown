#!/usr/bin/env python3
"""Draws the UsageBar app icon and writes Resources/AppIcon.iconset.

Every shape here is a signed distance field, so the edges are antialiased from the
distance itself rather than by supersampling, and there is no image library to install.
Run it after changing anything below; `scripts/build-app.sh` turns the iconset into
AppIcon.icns with `iconutil`.
"""

import math
import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")

# --- the design -------------------------------------------------------------

BODY_INSET = 96.0          # macOS leaves the outer ring of the canvas empty
BODY_RADIUS = 190.0

CX, CY = 512.0, 498.0
RING_R = 268.0             # centre line of the gauge band
RING_W = 47.0              # half the band's thickness
GAUGE_START = 135.0        # degrees, screen convention: 0 right, 90 down
GAUGE_SWEEP = 270.0
FILLED = 0.68              # how much of the gauge is drawn as "remaining"

NEEDLE_LEN = 196.0
NEEDLE_HALF = 14.0
HUB_R = 41.0
HUB_INNER_R = 17.0

TOP = (0x3B, 0x46, 0x54)
BOTTOM = (0x12, 0x16, 0x1D)
TRACK = (0xFF, 0xFF, 0xFF, 0.12)
ARC_FROM = (0x4A, 0xDE, 0x80)
ARC_TO = (0x22, 0xD3, 0xEE)
METAL = (0xF6, 0xF9, 0xFC)


def rounded_rect(px, py, cx, cy, half_w, half_h, radius):
    dx = abs(px - cx) - (half_w - radius)
    dy = abs(py - cy) - (half_h - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def segment(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    denom = vx * vx + vy * vy
    t = 0.0 if denom == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / denom))
    return math.hypot(wx - t * vx, wy - t * vy)


def arc_field(px, py, start_deg, sweep_deg):
    """Distance to an arc of round-capped band, plus how far along it the point sits."""
    dx, dy = px - CX, py - CY
    radius = math.hypot(dx, dy)
    angle = math.degrees(math.atan2(dy, dx))
    offset = (angle - start_deg) % 360.0
    if offset <= sweep_deg:
        return abs(radius - RING_R) - RING_W, offset / sweep_deg if sweep_deg else 0.0
    # Outside the sweep: the nearest round cap decides.
    best, at_start = None, True
    for end_deg, is_start in ((start_deg, True), (start_deg + sweep_deg, False)):
        rad = math.radians(end_deg)
        d = math.hypot(px - (CX + RING_R * math.cos(rad)), py - (CY + RING_R * math.sin(rad))) - RING_W
        if best is None or d < best:
            best, at_start = d, is_start
    return best, 0.0 if at_start else 1.0


def coverage(distance):
    """1 inside, 0 outside, a smooth pixel-wide edge between."""
    return max(0.0, min(1.0, 0.5 - distance))


def over(dst, src, alpha):
    if alpha <= 0:
        return dst
    return tuple(s * alpha + d * (1 - alpha) for d, s in zip(dst, src))


def render():
    needle_deg = GAUGE_START + GAUGE_SWEEP * FILLED
    needle_rad = math.radians(needle_deg)
    nx = CX + NEEDLE_LEN * math.cos(needle_rad)
    ny = CY + NEEDLE_LEN * math.sin(needle_rad)

    half = (SIZE - 2 * BODY_INSET) / 2.0
    pixels = bytearray(SIZE * SIZE * 4)
    index = 0

    for y in range(SIZE):
        py = y + 0.5
        for x in range(SIZE):
            px = x + 0.5

            body = coverage(rounded_rect(px, py, 512.0, 512.0, half, half, BODY_RADIUS))
            if body <= 0.0:
                index += 4
                continue

            # Body: a vertical gradient, lifted very slightly at the top edge.
            t = max(0.0, min(1.0, (py - BODY_INSET) / (2 * half)))
            eased = t * t * (3 - 2 * t)
            colour = [a + (b - a) * eased for a, b in zip(TOP, BOTTOM)]
            sheen = max(0.0, 1.0 - t * 4.0) * 14.0
            colour = [min(255.0, c + sheen) for c in colour]

            # Gauge track, then the filled part of it.
            d_track, _ = arc_field(px, py, GAUGE_START, GAUGE_SWEEP)
            a_track = coverage(d_track)
            if a_track > 0:
                colour = over(colour, TRACK[:3], a_track * TRACK[3])

            d_arc, along = arc_field(px, py, GAUGE_START, GAUGE_SWEEP * FILLED)
            a_arc = coverage(d_arc)
            if a_arc > 0:
                arc_colour = [a + (b - a) * along for a, b in zip(ARC_FROM, ARC_TO)]
                colour = over(colour, arc_colour, a_arc)

            # Needle and hub.
            a_needle = coverage(segment(px, py, CX, CY, nx, ny) - NEEDLE_HALF)
            a_hub = coverage(math.hypot(px - CX, py - CY) - HUB_R)
            metal = max(a_needle, a_hub)
            if metal > 0:
                colour = over(colour, METAL, metal)
            a_inner = coverage(math.hypot(px - CX, py - CY) - HUB_INNER_R)
            if a_inner > 0:
                inner = [a + (b - a) * 0.55 for a, b in zip(TOP, BOTTOM)]
                colour = over(colour, inner, a_inner)

            pixels[index] = int(colour[0] * body + 0.5)
            pixels[index + 1] = int(colour[1] * body + 0.5)
            pixels[index + 2] = int(colour[2] * body + 0.5)
            pixels[index + 3] = int(255 * body + 0.5)
            index += 4

    return pixels


def downsample(src, src_size, dst_size):
    """Box filter on premultiplied values, so edges do not pick up a dark fringe."""
    factor = src_size // dst_size
    out = bytearray(dst_size * dst_size * 4)
    area = factor * factor
    for y in range(dst_size):
        for x in range(dst_size):
            r = g = b = a = 0
            for sy in range(y * factor, (y + 1) * factor):
                row = sy * src_size * 4
                for sx in range(x * factor, (x + 1) * factor):
                    i = row + sx * 4
                    alpha = src[i + 3]
                    r += src[i] * alpha
                    g += src[i + 1] * alpha
                    b += src[i + 2] * alpha
                    a += alpha
            o = (y * dst_size + x) * 4
            if a:
                out[o] = min(255, round(r / a))
                out[o + 1] = min(255, round(g / a))
                out[o + 2] = min(255, round(b / a))
            out[o + 3] = round(a / area)
    return out


def write_png(path, size, pixels):
    def chunk(tag, payload):
        data = tag + payload
        return struct.pack(">I", len(payload)) + data + struct.pack(">I", zlib.crc32(data))

    stride = size * 4
    raw = b"".join(b"\x00" + bytes(pixels[y * stride:(y + 1) * stride]) for y in range(size))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def main():
    iconset = os.path.join(OUT, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)

    print("rendering %dx%d" % (SIZE, SIZE))
    master = render()

    wanted = {
        16: ["icon_16x16.png"],
        32: ["icon_16x16@2x.png", "icon_32x32.png"],
        64: ["icon_32x32@2x.png"],
        128: ["icon_128x128.png"],
        256: ["icon_128x128@2x.png", "icon_256x256.png"],
        512: ["icon_256x256@2x.png", "icon_512x512.png"],
        1024: ["icon_512x512@2x.png"],
    }

    for size in sorted(wanted, reverse=True):
        pixels = master if size == SIZE else downsample(master, SIZE, size)
        for name in wanted[size]:
            write_png(os.path.join(iconset, name), size, pixels)
        print("  %4d -> %s" % (size, ", ".join(wanted[size])))


if __name__ == "__main__":
    main()

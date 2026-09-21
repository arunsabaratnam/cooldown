#!/usr/bin/env python3
"""Draws the pictures in the README: the menu bar strip and the open panel.

These are drawings of the interface, not screenshots of a running app. They are SVG so
the text stays sharp at any width GitHub renders them at, and so they can be corrected
by editing this file rather than by retaking a screenshot.
"""

import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

FONT = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif"
WHITE = "#F5F5F7"
GREEN = "#4ADE80"
ORANGE = "#FB923C"
RED = "#F87171"

SECONDARY = 0.78
TERTIARY = 0.56


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, body, size=11, fill=WHITE, opacity=1.0, weight="400", anchor="start"):
    return (
        f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" '
        f'font-weight="{weight}" fill="{fill}" fill-opacity="{opacity}" '
        f'text-anchor="{anchor}">{esc(body)}</text>'
    )


def desktop(width, height, radius=0):
    """The wallpaper the interface sits on."""
    return (
        "<defs>"
        '<linearGradient id="sky" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0%" stop-color="#2B2E5A"></stop>'
        '<stop offset="48%" stop-color="#2A2348"></stop>'
        '<stop offset="100%" stop-color="#3E2745"></stop>'
        "</linearGradient>"
        '<radialGradient id="glowA" cx="18%" cy="0%" r="70%">'
        '<stop offset="0%" stop-color="#5A4490" stop-opacity="0.85"></stop>'
        '<stop offset="100%" stop-color="#5A4490" stop-opacity="0"></stop>'
        "</radialGradient>"
        '<radialGradient id="glowB" cx="92%" cy="10%" r="65%">'
        '<stop offset="0%" stop-color="#1F7B92" stop-opacity="0.75"></stop>'
        '<stop offset="100%" stop-color="#1F7B92" stop-opacity="0"></stop>'
        "</radialGradient>"
        "</defs>"
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="{radius}" fill="url(#sky)"></rect>'
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="{radius}" fill="url(#glowA)"></rect>'
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="{radius}" fill="url(#glowB)"></rect>'
    )


def gauge_glyph(cx, cy, scale=1.0, colour=WHITE, opacity=0.93):
    """The same gauge as the app icon, drawn as a line mark for the menu bar."""
    s = scale
    return (
        f'<g transform="translate({cx - 8 * s},{cy - 8 * s}) scale({s})" '
        f'stroke="{colour}" stroke-opacity="{opacity}" fill="none" '
        'stroke-width="1.7" stroke-linecap="round">'
        '<path d="M4.32 11.68 A 5.2 5.2 0 1 1 11.68 11.68"></path>'
        '<path d="M8 8 L 10.7 5.62"></path>'
        f'<circle cx="8" cy="8" r="1.25" fill="{colour}" fill-opacity="{opacity}" stroke="none"></circle>'
        "</g>"
    )


def approx_width(body, size):
    """Good enough to lay out a mock menu bar without a font metrics library."""
    return len(body) * size * 0.54


# --- the menu bar -----------------------------------------------------------

def menu_bar_svg():
    w, bar, below = 960, 26, 34
    h = bar + below
    parts = [desktop(w, h)]
    parts.append(f'<rect x="0" y="0" width="{w}" height="{bar}" fill="#121218" fill-opacity="0.42"></rect>')

    x = 12
    for i, name in enumerate(("Finder", "File", "Edit", "View", "Go", "Window", "Help")):
        weight = "600" if i == 0 else "400"
        parts.append(text(x, 17.5, name, size=13, opacity=0.93, weight=weight))
        x += approx_width(name, 13) + 18

    # The right-hand cluster is laid out from the right edge inwards.
    right = w - 12
    clock = "Mon 21 Sep   8:58 PM"
    parts.append(text(right, 17.5, clock, size=13, opacity=0.93, anchor="end"))
    right -= approx_width(clock, 13) + 14

    label = "C 100%  X 100%"
    label_w = approx_width(label, 13)
    item_w = 16 + 5 + label_w + 14
    item_x = right - item_w
    parts.append(
        f'<rect x="{item_x:.1f}" y="3" width="{item_w:.1f}" height="20" rx="4" '
        'fill="#FFFFFF" fill-opacity="0.16"></rect>'
    )
    parts.append(gauge_glyph(item_x + 15, 13, scale=1.0))
    parts.append(text(item_x + 26, 17.5, label, size=13, opacity=0.95))
    right = item_x - 8

    stroke = 'stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="1.4" fill="none" stroke-linecap="round"'
    glyphs = [
        # control centre
        f'<g transform="translate({{x}},4)"><path d="M2.6 5.1h10.8" {stroke}></path>'
        f'<path d="M2.6 10.9h10.8" {stroke}></path>'
        '<circle cx="6.1" cy="5.1" r="1.75" fill="#FFFFFF" fill-opacity="0.9"></circle>'
        '<circle cx="10.1" cy="10.9" r="1.75" fill="#FFFFFF" fill-opacity="0.9"></circle></g>',
        # search
        f'<g transform="translate({{x}},4)"><circle cx="7.1" cy="7.1" r="4.3" {stroke}></circle>'
        f'<path d="M10.3 10.3 13.4 13.4" {stroke}></path></g>',
        # wifi
        f'<g transform="translate({{x}},4)"><path d="M2.2 6.1a8.6 8.6 0 0 1 11.6 0" {stroke}></path>'
        f'<path d="M4.4 8.5a5.4 5.4 0 0 1 7.2 0" {stroke}></path>'
        f'<path d="M6.5 10.9a2.4 2.4 0 0 1 3 0" {stroke}></path>'
        '<circle cx="8" cy="12.9" r="0.95" fill="#FFFFFF" fill-opacity="0.9"></circle></g>',
        # battery
        f'<g transform="translate({{x}},6)"><rect x="0.7" y="0.4" width="20.6" height="9.2" rx="3" '
        'stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="1.2" fill="none"></rect>'
        '<rect x="2.3" y="2" width="13.2" height="6" rx="1.7" fill="#FFFFFF" fill-opacity="0.9"></rect>'
        '<path d="M23.2 3.4v3.2a2.6 2.6 0 0 0 0-3.2z" fill="#FFFFFF" fill-opacity="0.55"></path></g>',
    ]
    widths = [16, 16, 16, 25]
    for glyph, gw in zip(glyphs, widths):
        right -= gw
        parts.append(glyph.format(x=round(right, 1)))
        right -= 12

    scale = 2
    body = "".join(parts)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * scale}" height="{h * scale}" '
        f'viewBox="0 0 {w * scale} {h * scale}" role="img" '
        'aria-label="The macOS menu bar with Cooldown showing 100% of the 5-hour window left for Claude and Codex">'
        f'<g transform="scale({scale})">{body}</g></svg>\n'
    )


# --- the panel --------------------------------------------------------------

PANEL_W = 300
PAD = 14
INNER = PANEL_W - 2 * PAD

# A fresh 5-hour window part-way through the week: the moment the cooldown button is
# for, and the only moment it is live. A window that has not started has no reset time
# to show, so those rows carry None and the app leaves the line out.
CLAUDE = [
    ("5-hour", 100, None, GREEN),
    ("Weekly", 38, "in 3d 4h", GREEN),
    ("Weekly (large model)", 18, "in 3d 4h", ORANGE),
]
CODEX = [
    ("5-hour", 100, None, GREEN),
    ("Weekly", 9, "in 5d 2h", RED),
]


def divider(y):
    return (
        f'<rect x="0" y="{y}" width="{PANEL_W}" height="1" '
        'fill="#FFFFFF" fill-opacity="0.11"></rect>'
    )


def window_row(y, label, remaining, resets, tint):
    parts = [
        text(PAD, y + 9, label, size=11, opacity=SECONDARY),
        f'<text x="{PANEL_W - PAD}" y="{y + 9}" font-family="{FONT}" font-size="11" '
        f'text-anchor="end" fill="{WHITE}">'
        f'<tspan font-weight="600">{remaining}%</tspan>'
        f'<tspan fill-opacity="{SECONDARY}"> left</tspan></text>',
        f'<rect x="{PAD}" y="{y + 15}" width="{INNER}" height="6" rx="3" '
        'fill="#FFFFFF" fill-opacity="0.13"></rect>',
        f'<rect x="{PAD}" y="{y + 15}" width="{INNER * remaining / 100:.1f}" height="6" rx="3" '
        f'fill="{tint}"></rect>',
    ]
    if resets is None:
        return parts, y + 33
    parts.append(text(PAD, y + 34, "resets " + resets, size=10, opacity=TERTIARY))
    return parts, y + 42


def provider_block(y, name, source, rows):
    parts = [
        text(PAD, y + 11, name, size=12, weight="600"),
        text(PANEL_W - PAD, y + 11, "just now", size=10, opacity=TERTIARY, anchor="end"),
    ]
    y += 19
    for row in rows:
        chunk, y = window_row(y, *row)
        parts += chunk
    parts.append(text(PAD, y + 8, source, size=9, opacity=TERTIARY))
    return parts, y + 16


def panel_svg():
    parts = []
    y = 0

    parts.append(text(PAD, 24, "Usage", size=13, weight="600"))
    parts.append(text(PANEL_W - PAD, 24, "Updated just now", size=10, opacity=TERTIARY, anchor="end"))
    y = 40
    parts.append(divider(y))
    y += 13

    chunk, y = provider_block(y, "Claude", "usage endpoint (live)", CLAUDE)
    parts += chunk
    y += 6
    chunk, y = provider_block(y, "Codex", "codex app-server (live)", CODEX)
    parts += chunk

    y += 6
    parts.append(divider(y))
    y += 11

    parts.append(
        f'<rect x="{PAD}" y="{y}" width="{INNER}" height="30" rx="6" '
        'fill="#FFFFFF" fill-opacity="0.15" stroke="#FFFFFF" stroke-opacity="0.18"></rect>'
    )
    # Centre the glyph and the label as one group, rather than guessing at offsets.
    button_label = "Start the 5-hour cooldown"
    label_w = approx_width(button_label, 13)
    glyph_w, gap = 16 * 0.85, 7
    group_left = PANEL_W / 2 - (glyph_w + gap + label_w) / 2
    parts.append(gauge_glyph(group_left + glyph_w / 2, y + 15, scale=0.85))
    parts.append(
        text(group_left + glyph_w + gap + label_w / 2, y + 19, button_label, size=13, anchor="middle")
    )
    y += 41

    parts.append(divider(y))
    y += 10
    parts.append(text(PAD, y + 12, "Settings", size=11, opacity=SECONDARY))
    parts.append(text(PANEL_W - PAD, y + 12, "Quit", size=11, opacity=SECONDARY, anchor="end"))
    y += 26

    panel_h = round(y)
    margin, scale = 22, 2
    w = (PANEL_W + margin * 2) * scale
    h = (panel_h + margin * 2) * scale

    shell = (
        f'<rect x="0" y="0" width="{PANEL_W}" height="{panel_h}" rx="12" '
        'fill="#26262C" fill-opacity="0.86" stroke="#FFFFFF" stroke-opacity="0.16"></rect>'
    )

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" role="img" '
        'aria-label="The Cooldown panel, listing the 5-hour and weekly quota left for Claude and Codex">'
        f'<g transform="scale({scale})">'
        + desktop(PANEL_W + margin * 2, panel_h + margin * 2, radius=10)
        + f'<g transform="translate({margin},{margin})">'
        + shell
        + "".join(parts)
        + "</g></g></svg>\n"
    )


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, svg in (("menu-bar.svg", menu_bar_svg()), ("panel.svg", panel_svg())):
        path = os.path.join(OUT, name)
        with open(path, "w") as handle:
            handle.write(svg)
        print("wrote %s (%d bytes)" % (name, len(svg)))


if __name__ == "__main__":
    main()

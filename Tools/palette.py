"""OKLCH-alapú palettagenerátor.

Miért nem kézzel írt hexek: az „azonos világosságú akcentus" követelmény
sRGB-ben nem ellenőrizhető — a #F2966B és a #8ED0BE szemre hasonló, de a
mért világosságuk eltér. Az OKLab perceptuális, ezért ott a rögzített L
tényleg azonos érzékelt világosságot jelent. A szövegkontrasztot pedig
WCAG-képlettel MÉRJÜK, nem saccoljuk.
"""
import math

# --- sRGB <-> OKLab -------------------------------------------------------
def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def _linear_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055

def oklch_to_rgb(L, C, H):
    a = C * math.cos(math.radians(H))
    b = C * math.sin(math.radians(H))
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    r = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return [_linear_to_srgb(x) for x in (r, g, bl)]

def in_gamut(rgb):
    return all(-0.0005 <= c <= 1.0005 for c in rgb)

def oklch_hex(L, C, H):
    """Gamut-on kívül eső színnél a KRÓMÁT csökkentjük, nem a világosságot:
    így az „azonos világosság" feltétel végig megmarad."""
    c = C
    while c > 0 and not in_gamut(oklch_to_rgb(L, c, H)):
        c -= 0.002
    r, g, b = [max(0.0, min(1.0, x)) for x in oklch_to_rgb(L, c, H)]
    return (round(r * 255) << 16) | (round(g * 255) << 8) | round(b * 255)

# --- WCAG kontraszt -------------------------------------------------------
def luminance(hexv):
    r, g, b = ((hexv >> 16) & 255) / 255, ((hexv >> 8) & 255) / 255, (hexv & 255) / 255
    r, g, b = _srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def ink_for(accent_hex, hue):
    """Szöveg az akcentuson: fehér vagy a saját árnyalat sötét tónusa —
    amelyik MÉRHETŐEN jobban olvasható."""
    white = 0xFFFFFF
    dark = oklch_hex(0.26, 0.055, hue)
    return (white, contrast(accent_hex, white)) if contrast(accent_hex, white) >= contrast(accent_hex, dark) \
        else (dark, contrast(accent_hex, dark))

# --- Harmóniák ------------------------------------------------------------
SCHEMES = {
    "komplementer":        lambda h: (h, (h + 180) % 360, (h + 210) % 360),
    "osztott-komplementer":lambda h: (h, (h + 150) % 360, (h + 210) % 360),
    "triád":               lambda h: (h, (h + 120) % 360, (h + 240) % 360),
    "analóg":              lambda h: (h, (h + 34) % 360, (h - 34) % 360),
    "tetrád":              lambda h: (h, (h + 90) % 360, (h + 200) % 360),
    "kettős":              lambda h: (h, (h + 60) % 360, (h + 190) % 360),
}

# Hat akcentus ugyanabból a harmónia-családból.
#
# Miért kell: három akcentussal négy platformnál már ismétlődik a szín, és a
# kártyák egymáshoz hasonlítanak. Az ELSŐ HÁROM ÁRNYALAT SZÁNDÉKOSAN AZONOS
# a három akcentusos változatéval — így a meglévő platformok színe nem
# változik, csak a negyediktől kezdve jön új.
#
# A kiterjesztés családonként más, mert a puszta felezés az analóg sémánál
# ütközést adna: ott a második és harmadik árnyalat FELEZŐPONTJA épp a
# vezető árnyalatra esik vissza.
SCHEMES6 = {
    "komplementer":        lambda h: (h, h + 180, h + 210, h + 30,  h + 150, h + 330),
    "osztott-komplementer":lambda h: (h, h + 150, h + 210, h + 30,  h + 180, h + 330),
    "triád":               lambda h: (h, h + 120, h + 240, h + 60,  h + 180, h + 300),
    "analóg":              lambda h: (h, h + 34,  h - 34,  h + 68,  h - 68,  h + 102),
    "tetrád":              lambda h: (h, h + 90,  h + 200, h + 45,  h + 145, h + 290),
    "kettős":              lambda h: (h, h + 60,  h + 190, h + 30,  h + 130, h + 250),
}

def hues6(scheme, h):
    """A hat árnyalat 0–360 közé normalizálva."""
    return [x % 360 for x in SCHEMES6[scheme](h)]

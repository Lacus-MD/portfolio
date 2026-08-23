"""Téma szerinti app-ikonok.

Ugyanaz a szikragörbe, mint az alapikonon (`Icon/generate.py`), csak a
színeket az AKTUÁLIS témákból olvassuk ki — így az ikon és az app egy
nyelvet beszél. Bemenet: `Shared/Design/AppTheme.swift`; kimenet:
`App/Resources/Assets.xcassets/AppIcon-<id>.appiconset/`.

Futtatás a projekt gyökeréből:  python3 Tools/gen_icons.py
"""
import json, os, re, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "App/Resources/Assets.xcassets")
S, SS = 1024, 4
W = S * SS


def themes():
    src = open(os.path.join(ROOT, "Shared/Design/AppTheme.swift")).read()
    out = []
    for tid, body in re.findall(r"static let (\w+) = make\((.*?)\n    \)", src, re.S):
        def hexv(key):
            m = re.search(rf"\b{key}: 0x([0-9A-Fa-f]{{6}})", body)
            return int(m.group(1), 16) if m else None
        accent = re.search(r"\baccents:\s*\[0x([0-9A-Fa-f]{6})", body)
        out.append({
            "id": tid,
            "deep": hexv("canvasDark"), "shell": hexv("cardDark"),
            "accent": int(accent.group(1), 16) if accent else None,
        })

    # A monokróm család közös gyárfüggvényt használ: mindegyiknek ugyanaz
    # a szürke háttere, és csak az egyetlen megadott akcentusa tér el.
    for _, body in re.findall(r"static let (\w+) = makeMonochrome\((.*?)\n    \)", src, re.S):
        tid = re.search(r'\bid:\s*"([^"]+)"', body)
        accent = re.search(r"\baccent:\s*0x([0-9A-Fa-f]{6})", body)
        if tid and accent:
            out.append({
                "id": tid.group(1),
                "deep": 0x090909, "shell": 0x191919,
                "accent": int(accent.group(1), 16),
            })
    return out


def rgb(v): return ((v >> 16) & 255, (v >> 8) & 255, v & 255)
def lerp(a, b, t): return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def background(top, bottom):
    img = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(img)
    for i in range(W):
        d.line([(0, i), (W, i)], fill=lerp(top, bottom, i / W))
    # Lágy fény a bal felső sarokból. Elmosott kör, nem lineáris overlay:
    # az utóbbi látható sáv-határt hagyott (lásd Icon/generate.py).
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).ellipse([-W * 0.35, -W * 0.45, W * 0.85, W * 0.75], fill=48)
    mask = mask.filter(ImageFilter.GaussianBlur(W * 0.13))
    return Image.composite(Image.new("RGB", (W, W), (255, 255, 255)), img, mask)


def curve_points():
    """A két végpont a kereten KÍVÜL van, hogy a vonal kifusson — enélkül a
    kitöltés alja éles függőleges élet hagy ott, ahol a poligon bezárul."""
    raw = [(-0.12, 0.70), (0.06, 0.64), (0.22, 0.58), (0.36, 0.64), (0.50, 0.45),
           (0.63, 0.51), (0.78, 0.30), (0.95, 0.25), (1.12, 0.19)]
    pts, ext = [], [raw[0]] + raw + [raw[-1]]
    for i in range(len(ext) - 3):
        p0, p1, p2, p3 = ext[i:i + 4]
        for j in range(25):
            t = j / 24; t2, t3 = t * t, t * t * t
            x = 0.5 * ((2*p1[0]) + (-p0[0]+p2[0])*t + (2*p0[0]-5*p1[0]+4*p2[0]-p3[0])*t2 + (-p0[0]+3*p1[0]-3*p2[0]+p3[0])*t3)
            y = 0.5 * ((2*p1[1]) + (-p0[1]+p2[1])*t + (2*p0[1]-5*p1[1]+4*p2[1]-p3[1])*t2 + (-p0[1]+3*p1[1]-3*p2[1]+p3[1])*t3)
            pts.append((x * W, y * W))
    return pts


def build(theme):
    img = background(rgb(theme["shell"]), rgb(theme["deep"])).convert("RGBA")
    pts = curve_points()
    line = rgb(theme["accent"])

    area = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(area).polygon(pts + [(pts[-1][0], W * 1.2), (pts[0][0], W * 1.2)],
                                 fill=line + (105,))
    fade = Image.new("L", (W, W))
    fd = ImageDraw.Draw(fade)
    for i in range(W):
        fd.line([(0, i), (W, i)], fill=max(0, 255 - int(255 * (i / W) ** 0.75)))
    area.putalpha(Image.composite(area.getchannel("A"), Image.new("L", (W, W)), fade))
    img.alpha_composite(area)
    ImageDraw.Draw(img).line(pts, fill=line + (255,), width=int(W * 0.046), joint="curve")
    return img.convert("RGB").resize((S, S), Image.LANCZOS)


CONTENTS = {
    "images": [{"filename": "icon.png", "idiom": "universal",
                "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1},
}

names = []
for theme in themes():
    folder = os.path.join(ASSETS, f"AppIcon-{theme['id']}.appiconset")
    os.makedirs(folder, exist_ok=True)
    build(theme).save(os.path.join(folder, "icon.png"))
    json.dump(CONTENTS, open(os.path.join(folder, "Contents.json"), "w"), indent=2)
    names.append(f"AppIcon-{theme['id']}")
    print("kész:", theme["id"])

print("\nASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES:", " ".join(names))

"""A Portfólió app-ikonja: az app saját szikragörbéje, glaucous akcentussal.

Két tanulság az első próbából:
  - a görbének KI KELL FUTNIA a képből mindkét oldalon, különben a kitöltés
    alja éles függőleges élet hagy ott, ahol a poligon bezárul;
  - a színátmenetre tett átlós overlay látható sávot csinált — helyette
    elmosott radiális fény kell.
"""
from PIL import Image, ImageDraw, ImageFilter

S, SS = 1024, 4
W = S * SS
GLAUCOUS = (96, 130, 182)

def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))

def background(top, bottom, glow=True):
    img = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(img)
    for i in range(W):
        d.line([(0, i), (W, i)], fill=lerp(top, bottom, i / W))
    if glow:
        # Lágy fény a bal felső sarokból: elmosott kör, nem lineáris overlay,
        # így nem keletkezik látható sáv-határ.
        mask = Image.new("L", (W, W), 0)
        ImageDraw.Draw(mask).ellipse([-W*0.35, -W*0.45, W*0.85, W*0.75], fill=54)
        mask = mask.filter(ImageFilter.GaussianBlur(W * 0.13))
        img = Image.composite(Image.new("RGB", (W, W), (255, 255, 255)), img, mask)
    return img

def curve_points():
    """Emelkedő görbe visszaeséssel — egy portfólió nem egyenes vonal.
    A két végpont a kereten KÍVÜL van, hogy a vonal kifusson."""
    raw = [(-0.12, 0.70), (0.06, 0.64), (0.22, 0.58),
           (0.36, 0.64), (0.50, 0.45), (0.63, 0.51),
           (0.78, 0.30), (0.95, 0.25), (1.12, 0.19)]
    pts, ext = [], [raw[0]] + raw + [raw[-1]]
    for i in range(len(ext) - 3):
        p0, p1, p2, p3 = ext[i:i + 4]
        for j in range(25):
            t = j / 24; t2, t3 = t * t, t * t * t
            x = 0.5*((2*p1[0]) + (-p0[0]+p2[0])*t + (2*p0[0]-5*p1[0]+4*p2[0]-p3[0])*t2 + (-p0[0]+3*p1[0]-3*p2[0]+p3[0])*t3)
            y = 0.5*((2*p1[1]) + (-p0[1]+p2[1])*t + (2*p0[1]-5*p1[1]+4*p2[1]-p3[1])*t2 + (-p0[1]+3*p1[1]-3*p2[1]+p3[1])*t3)
            pts.append((x * W, y * W))
    return pts

def build(name, bg, line, fill_alpha):
    img = bg.convert("RGBA")
    pts = curve_points()

    # Terület-kitöltés: a poligon a kereten kívül zárul, tehát nincs látható él.
    area = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(area).polygon(pts + [(pts[-1][0], W * 1.2), (pts[0][0], W * 1.2)],
                                 fill=line + (fill_alpha,))
    fade = Image.new("L", (W, W))
    fd = ImageDraw.Draw(fade)
    for i in range(W):
        fd.line([(0, i), (W, i)], fill=max(0, 255 - int(255 * (i / W) ** 0.75)))
    area.putalpha(Image.composite(area.getchannel("A"), Image.new("L", (W, W)), fade))
    img.alpha_composite(area)

    ImageDraw.Draw(img).line(pts, fill=line + (255,), width=int(W * 0.046), joint="curve")

    out = img.convert("RGB").resize((S, S), Image.LANCZOS)
    out.save(f"{name}.png")
    return out

build("icon-A", background((128, 158, 203), (56, 82, 129)), (255, 255, 255), 95)
build("icon-B", background((36, 47, 70), (17, 22, 35)), GLAUCOUS, 110)
build("icon-C", background((249, 250, 252), (226, 232, 241), glow=False), GLAUCOUS, 85)

sheet = Image.new("RGB", (S * 3 + 160, S + 300), (242, 242, 247))
sd = ImageDraw.Draw(sheet)
for i, n in enumerate("ABC"):
    im = Image.open(f"icon-{n}.png")
    x = 40 + i * (S + 40)
    sheet.paste(im, (x, 40))
    sd.text((x + 8, S + 56), n, fill=(70, 70, 70))
    for j, sz in enumerate((180, 120, 76)):
        sheet.paste(im.resize((sz, sz), Image.LANCZOS), (x + 70 + j * 210, S + 100))
sheet.save("osszehasonlitas.png")
print("kész")

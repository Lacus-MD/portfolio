import sys; sys.path.insert(0, sys.argv[1])  # a palette.py mappája
from palette import oklch_hex, contrast, ink_for, SCHEMES, hues6

# (id, név, vezető árnyalat, séma, króma, világos héj?, leírás)
THEMES = [
    # A Pasztell VEZETŐ árnyalata 330° (rózsa), nem 35° (narancs). Az eredeti
    # handoff-paletta korallal vezetett, és mivel az első akcentust viszi az
    # app kiemelőszíne, az első platformkártya, a jelvény, a gyűrű és a
    # chipek, az egész app narancsnak látszott. A jelleg megmarad: a 330°-ból
    # ugyanúgy krémes vászon és mély szilva héj származik.
    ("pastel",    "Pasztell",   330, "osztott-komplementer", 0.085, False),
    ("ocean",     "Tenger",     205, "komplementer",         0.100, False),
    ("forest",    "Erdő",       148, "osztott-komplementer", 0.090, False),
    ("graphite",  "Grafit",     255, "analóg",               0.045, False),
    ("midnight",  "Éjkék",      272, "triád",                0.115, False),
    ("charcoal",  "Szén",       330, "kettős",               0.050, False),
    ("basalt",    "Bazalt",     185, "komplementer",         0.105, False),
    ("cherry",    "Cseresznye",  15, "triád",                0.100, False),
    ("paper",     "Papír",       95, "triád",                0.075, True),
    ("dawn",      "Hajnal",     350, "analóg",               0.095, True),
    ("sand",      "Homok",       65, "tetrád",               0.085, True),
    ("lavender",  "Levendula",  295, "osztott-komplementer", 0.090, True),
]

ACCENT_L = 0.76      # az eredeti korall mért világossága ~0.75
ICON_L   = 0.72
ICON_OFFSETS = [0, 40, 140, 200, 250, 310]

def hx(v): return f"0x{v:06X}"

report = []
out = []
for tid, name, hue, scheme, chroma, light_shell in THEMES:
    hs = hues6(scheme, hue)
    h1, h2, h3 = hs[0], hs[1], hs[2]
    # Hat akcentus, MIND azonos OKLab-világossággal: a kártyák így egymás
    # mellett kiegyensúlyozottak maradnak, csak az árnyalatuk tér el.
    accents = [oklch_hex(ACCENT_L, chroma, h) for h in hs]
    inks    = [ink_for(a, h)[0] for a, h in zip(accents, hs)]
    cons    = [ink_for(a, h)[1] for a, h in zip(accents, hs)]
    warm, cool, mid = accents[0], accents[1], accents[2]
    c_warm, c_cool, c_mid = cons[0], cons[1], cons[2]

    bg_c = min(0.016, chroma * 0.16)
    canvas_l = oklch_hex(0.972, bg_c, hue)
    card_l   = oklch_hex(0.995, bg_c * 0.4, hue) if not light_shell else oklch_hex(0.955, bg_c, hue)
    if light_shell: canvas_l = oklch_hex(0.998, bg_c * 0.3, hue)
    ink_l    = oklch_hex(0.300, min(0.040, chroma * 0.45), hue)
    canvas_d = oklch_hex(0.205, min(0.024, chroma * 0.25), hue)
    card_d   = oklch_hex(0.265, min(0.028, chroma * 0.28), hue)
    ink_d    = oklch_hex(0.945, min(0.014, chroma * 0.14), hue)
    shell_dd = oklch_hex(0.185, min(0.032, chroma * 0.32), hue)
    shell_d  = oklch_hex(0.255, min(0.036, chroma * 0.36), hue)
    if light_shell:
        shell_dl, shell_ll, ink_shell_l = oklch_hex(0.988, bg_c*0.5, hue), oklch_hex(0.952, bg_c, hue), ink_l
    else:
        shell_dl, shell_ll, ink_shell_l = shell_dd, shell_d, 0xFFFFFF
    # A nyereség/veszteség szín NEM akcentus. Az akcentusok témánként más
    # árnyalatból jönnek, tehát a második akcentus lehet lazac vagy sárga —
    # abból nyereséget olvasni félrevezető. Ez a kettő ezért rögzített
    # árnyalaton áll (zöld / piros), csak a króma követi a témát.
    positive = oklch_hex(0.640, min(0.130, max(0.075, chroma * 1.1)), 152)
    negative = oklch_hex(0.585, 0.150, 25)
    icons = [oklch_hex(ICON_L, chroma * 1.08, (hue + o) % 360) for o in ICON_OFFSETS]

    report.append((name, scheme, [(h1, warm, c_warm), (h2, cool, c_cool), (h3, mid, c_mid)],
                   contrast(canvas_l, ink_l), contrast(canvas_d, ink_d)))

    out.append(f'''    /// {name} — {scheme} harmónia a(z) {hue}°-os vezető árnyalatra.
    /// Akcentusok: {" / ".join(str(round(h)) + "°" for h in hs)}, azonos OKLab-világossággal ({ACCENT_L}).
    static let {tid} = AppTheme(
        id: "{tid}", name: "{name}",
        canvasLight: {hx(canvas_l)}, cardLight: {hx(card_l)}, inkLight: {hx(ink_l)},
        canvasDark: {hx(canvas_d)}, cardDark: {hx(card_d)}, inkDark: {hx(ink_d)},
        shellDeep: {hx(shell_dd)}, shell: {hx(shell_d)},
        shellDeepLight: {hx(shell_dl)}, shellLight: {hx(shell_ll)}, inkOnShellLight: {hx(ink_shell_l)},
        hasLightShell: {"true" if light_shell else "false"},
        accents: [{", ".join(hx(a) for a in accents)}],
        inkOnAccents: [{", ".join(hx(i) for i in inks)}],
        positive: {hx(positive)}, negative: {hx(negative)},
        iconHues: [{", ".join(hx(i) for i in icons)}]
    )
''')

open(sys.argv[2], "w").write("\n".join(out))

print(f"{'téma':<12}{'séma':<22}{'akcentus-árnyalatok':<26}{'szövegkontraszt az akcentuson':<32}{'tinta/vászon'}")
for name, scheme, accents, cl, cd in report:
    hues = "/".join(str(round(h)) for h, _, _ in accents)
    cons = " ".join(f"{c:.1f}" for _, _, c in accents)
    print(f"{name:<12}{scheme:<22}{hues:<26}{cons:<32}vil {cl:.1f} / söt {cd:.1f}")

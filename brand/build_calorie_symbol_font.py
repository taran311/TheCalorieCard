# Builds CalorieSymbol-*.ttf: one glyph, the calorie currency symbol, at
# U+E000 (private use), in three weights. Same shape as CalorieSymbol in
# lib/ui/calorie_symbol.dart, sized like a currency sign: the C sits on the
# baseline and reaches cap height, the strokes poke above and below (like $).
import math, sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

CAP = 700          # cap height in font units (1000 per em)
S = CAP / 60.0     # design box: the C runs from y 20 to 80
def tf(x, y, x0):  # design box → font units
    return (round((x - x0) * S), round((80 - y) * S))

def arc(cx, cy, r, a0, a1, n=14):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]

def c_outline(h):
    # Design coords are y-down (like the SVG); angles in that space.
    pts = []
    pts += [(74, 20 - h), (44, 20 - h)]
    pts += arc(44, 42, 22 + h, 270, 180)[1:]
    pts += [(22 - h, 58)]
    pts += arc(44, 58, 22 + h, 180, 90)[1:]
    pts += [(74, 80 + h)]
    pts += arc(74, 80, h, 90, -90)[1:]          # round end, bottom
    pts += [(44, 80 - h)]
    pts += arc(44, 58, 22 - h, 90, 180)[1:]
    pts += [(22 + h, 42)]
    pts += arc(44, 42, 22 - h, 180, 270)[1:]
    pts += [(74, 20 + h)]
    pts += arc(74, 20, h, 90, -90)[1:-1]        # round end, top
    return pts

def stadium(x, y0, y1, h):
    pts = arc(x, y0, h, 180, 360)                # top cap
    pts += arc(x, y1, h, 0, 180)                 # bottom cap
    return pts

def build(name, weight, sw, tw, out):
    h, th = sw / 2.0, tw / 2.0
    x0 = 22 - h - 4                              # small left bearing
    right = 74 + h + 4
    adv = round((right - x0) * S)
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder([".notdef", "calsym", "space"])
    fb.setupCharacterMap({0xE000: "calsym", 0x20: "space"})
    pen = TTGlyphPen(None)
    def poly(pts, reverse=False):
        p = [tf(x, y, x0) for x, y in pts]
        # Every shape goes the same way round (clockwise in font space, the
        # TrueType convention), so where the strokes cross the C they add
        # up instead of cutting a hole.
        area = sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1]
                   for i in range(len(p)))
        if area > 0: p = p[::-1]  # anticlockwise: turn it round
        pen.moveTo(p[0])
        for q in p[1:]: pen.lineTo(q)
        pen.closePath()
    poly(c_outline(h))
    poly(stadium(48, 7, 14, th))
    poly(stadium(48, 86, 93, th))
    calsym = pen.glyph()
    empty = TTGlyphPen(None).glyph()
    fb.setupGlyf({".notdef": empty, "calsym": calsym, "space": empty})
    fb.setupHorizontalMetrics({".notdef": (500, 0), "calsym": (adv, 0), "space": (250, 0)})
    fb.setupHorizontalHeader(ascent=950, descent=-250)
    fb.setupNameTable({"familyName": "CalorieSymbol", "styleName": name,
                       "uniqueFontIdentifier": "CalorieSymbol-" + name,
                       "fullName": "CalorieSymbol " + name, "psName": "CalorieSymbol-" + name})
    fb.setupOS2(sTypoAscender=950, sTypoDescender=-250, usWinAscent=950, usWinDescent=250,
                usWeightClass=weight, sCapHeight=CAP, sxHeight=500)
    fb.setupPost()
    fb.save(out)

# Run from the project folder: python brand/build_calorie_symbol_font.py
d = sys.argv[1] if len(sys.argv) > 1 else "assets/fonts"
build("Regular", 400, 10, 7, d + "/CalorieSymbol-Regular.ttf")
build("SemiBold", 600, 12, 8.5, d + "/CalorieSymbol-SemiBold.ttf")
build("Bold", 800, 14, 10, d + "/CalorieSymbol-Bold.ttf")
print("ok")

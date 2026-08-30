"""Generate POI marker PNGs for the MapLibre vector map.

One 48x48 icon per waypoint type: an EVEE accent disc with a white ring and
a simple white glyph, readable at 24 px on-map. Written to
assets/map_markers/poi_<type>.png and loaded at runtime via
StyleController.addImage (symbol layers need pre-rendered bitmaps; there is
no font-based icon path in maplibre 0.2.2).
"""
import os
from PIL import Image, ImageDraw

OUT = r"E:\AI\esk8os_mobile\assets\map_markers"
ACCENT = (185, 80, 215, 235)
WHITE = (255, 255, 255, 255)
SIZE = 48


def base_disc():
    img = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, 46, 46], fill=ACCENT, outline=WHITE, width=4)
    return img, d


def hazard(d):
    d.polygon([(24, 10), (41, 40), (7, 40)], outline=WHITE, width=3)
    d.line([(24, 20), (24, 28)], fill=WHITE, width=3)
    d.ellipse([(22.5, 31), (25.5, 34)], fill=WHITE)


def parking(d):
    d.rectangle([14, 12, 34, 36], outline=WHITE, width=3)
    d.line([20, 14, 20, 34], fill=WHITE, width=3)
    d.line([20, 24, 28, 14], fill=WHITE, width=3)


def charging(d):
    d.rectangle([16, 8, 32, 42], outline=WHITE, width=3)
    d.line([26, 12, 20, 26, 26, 26, 24, 38], fill=WHITE, width=3)


def water(d):
    d.polygon([(24, 12), (36, 30), (8, 32)], fill=(255, 255, 255, 225))


def viewpoint(d):
    d.polygon([(24, 10), (41, 38), (8, 38)], fill=(255, 255, 255, 225))
    d.line([6, 40, 42, 40], fill=WHITE, width=3)


def food(d):
    d.ellipse([12, 14, 26, 34], outline=WHITE, width=3)
    d.ellipse([22, 14, 40, 34], fill=(255, 255, 255, 225))


def restroom(d):
    d.ellipse([(17, 10), (26, 23)], fill=WHITE)
    d.polygon([(24, 26), (14, 42), (34, 42)], fill=WHITE)


def shelter(d):
    d.polygon([(24, 8), (42, 24), (6, 24)], fill=WHITE)
    d.rectangle([12, 24, 34, 40], outline=WHITE, width=3)


def repair(d):
    d.line([12, 36, 30, 12], fill=WHITE, width=4)
    d.ellipse([(28, 10), (40, 22)], outline=WHITE, width=3)


def trailhead(d):
    d.rectangle([21, 8, 27, 40], fill=WHITE)
    d.rectangle([21, 8, 38, 20], fill=WHITE)


def scenic(d):
    d.ellipse([10, 12, 38, 40], outline=WHITE, width=3)
    d.ellipse([(20, 20), (28, 28)], fill=WHITE)


def note(d):
    d.rectangle([12, 12, 36, 40], outline=WHITE, width=3)
    for y in (16, 22, 28):
        d.line([16, y, 32, y], fill=WHITE, width=3)


GLYPHS = {
    "trailhead": None,
    "hazard": hazard,
    "parking": parking,
    "charging": charging,
    "water": water,
    "viewpoint": viewpoint,
    "scenic": scenic,
    "food": food,
    "restroom": None,
    "shelter": shelter,
    "repair": repair,
    "note": None,
}


def render(kind):
    img = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, 46, 46], fill=ACCENT, outline=WHITE, width=4)
    if kind == "hazard":
        hazard(d)
    elif kind == "parking":
        d.rectangle([14, 12, 34, 36], outline=WHITE, width=3)
        d.line([20, 14, 20, 34], fill=WHITE, width=3)
    elif kind == "charging":
        d.rectangle([18, 10, 32, 40], outline=WHITE, width=3)
    elif kind == "water":
        d.ellipse([15, 15, 33, 33], fill=WHITE)
    elif kind == "viewpoint":
        d.polygon([(24, 12), (40, 36), (8, 38)], fill=(255, 255, 255, 225))
    elif kind == "scenic":
        d.ellipse([14, 14, 34, 34], outline=WHITE, width=3)
        d.ellipse([(21, 21), (27, 27)], fill=WHITE)
    elif kind == "food":
        d.rectangle([16, 12, 22, 38], fill=WHITE)
        d.ellipse([26, 20, 36, 30], outline=WHITE, width=3)
    elif kind == "restroom":
        d.ellipse([(16, 12), (26, 32)], fill=WHITE)
        d.rectangle([(24, 14), (34, 36)], fill=WHITE)
    elif kind == "shelter":
        shelter(d)
    elif kind == "repair":
        d.rectangle([14, 22, 36, 28], fill=WHITE)
        d.ellipse([(20, 10), (30, 20)], fill=WHITE)
    # trailhead / note: plain disc (the pin look)
    return img


os.makedirs(OUT, exist_ok=True)
for kind in [
    "trailhead", "hazard", "parking", "charging", "water", "viewpoint",
    "scenic", "food", "restroom", "shelter", "repair", "note",
]:
    render(kind).save(os.path.join(OUT, f"poi_{kind}.png"))
print("wrote", len(GLYPHS), "icons to", OUT)

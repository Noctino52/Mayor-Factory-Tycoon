"""
Classic clothing for the three traders, for Mayor's Factory Tycoon.

Run:
    python modeling/clothing.py

Outputs:
    modeling/export/clothing/<name>_shirt.png
    modeling/export/clothing/<name>_pants.png

Upload each to Roblox as classic clothing, then put the asset ids in
Definitions - the game applies them to the NPC rigs.

The layout is Roblox's own, measured off the official templates rather than
guessed: every face of every body part is a rectangle on a 585x559 sheet, and
what is painted inside one rectangle appears on that face. The regions below
are those measurements. Anything outside them is never sampled.
"""

import os

from PIL import Image, ImageDraw

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(SCRIPT_DIR, "export", "clothing")

SHEET = (585, 559)

# name: (x, y, width, height)
REGIONS = {
    "torso_up": (231, 8, 128, 64),
    "torso_right": (165, 74, 64, 128),
    "torso_front": (231, 74, 128, 128),
    "torso_left": (361, 74, 64, 128),
    "torso_back": (427, 74, 128, 128),
    "torso_down": (231, 204, 128, 64),

    # Two limbs, each a cross: a cap on top, four sides, a cap underneath.
    # On a shirt these are the arms, on trousers the legs.
    "limbA_up": (217, 289, 64, 64),
    "limbA_outer": (19, 355, 64, 128),
    "limbA_back": (85, 355, 64, 128),
    "limbA_inner": (151, 355, 64, 128),
    "limbA_front": (217, 355, 64, 128),
    "limbA_down": (217, 485, 64, 64),

    "limbB_up": (308, 289, 64, 64),
    "limbB_front": (308, 355, 64, 128),
    "limbB_inner": (374, 355, 64, 128),
    "limbB_back": (440, 355, 64, 128),
    "limbB_outer": (506, 355, 64, 128),
    "limbB_down": (308, 485, 64, 64),
}

TORSO_FACES = ("torso_up", "torso_right", "torso_front", "torso_left", "torso_back", "torso_down")
LIMB_FACES = tuple(name for name in REGIONS if name.startswith("limb"))
LIMB_SIDES = ("limbA_outer", "limbA_back", "limbA_inner", "limbA_front",
              "limbB_front", "limbB_inner", "limbB_back", "limbB_outer")
LIMB_BOTTOMS = ("limbA_down", "limbB_down")


def sheet(background):
    """A blank template. The ground colour shows anywhere not painted over."""
    return Image.new("RGB", SHEET, background)


def fill(draw, region, colour):
    x, y, w, h = REGIONS[region]
    draw.rectangle([x, y, x + w - 1, y + h - 1], fill=colour)


def band(draw, region, colour, top, height, inset=0):
    """A horizontal band across a face, measured from the top of that face."""
    x, y, w, h = REGIONS[region]
    draw.rectangle([x + inset, y + top, x + w - 1 - inset, y + top + height - 1], fill=colour)


def stripe(draw, region, colour, left, width, top=0, height=None):
    """A vertical stripe down a face."""
    x, y, w, h = REGIONS[region]
    height = height or h
    draw.rectangle([x + left, y + top, x + left + width - 1, y + top + height - 1], fill=colour)


def plaid(draw, region, base, dark, light):
    """
    Buffalo check: a grid where the light squares and the dark squares sit on
    opposite diagonals and the base shows between them. Drawn in the region's
    own space, so the squares line up where two faces meet.
    """
    x, y, w, h = REGIONS[region]
    draw.rectangle([x, y, x + w - 1, y + h - 1], fill=base)

    step = 16
    for row, top in enumerate(range(0, h, step)):
        for column, left in enumerate(range(0, w, step)):
            even = (row % 2 == 0) == (column % 2 == 0)
            colour = light if (row % 2 == 0 and column % 2 == 0) else (dark if not even else None)
            if colour is None:
                continue
            draw.rectangle(
                [x + left, y + top, x + min(left + step, w) - 1, y + min(top + step, h) - 1],
                fill=colour,
            )


def save(image, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    image.save(path)
    print(f"[clothing] {path}")


# ---------------------------------------------------------------------------
# Mira - carpenter: plaid shirt under hi-vis braces, yellow work trousers
# ---------------------------------------------------------------------------

PLAID_BASE = (150, 58, 48)
PLAID_DARK = (96, 32, 26)
PLAID_LIGHT = (188, 92, 76)
HI_VIS = (232, 182, 44)
HI_VIS_DEEP = (198, 148, 22)
CUFF = (238, 236, 228)
LEATHER = (96, 62, 38)
BRASS = (198, 158, 74)


def build_mira_shirt():
    image = sheet(PLAID_BASE)
    draw = ImageDraw.Draw(image)

    for face in TORSO_FACES + LIMB_FACES:
        plaid(draw, face, PLAID_BASE, PLAID_DARK, PLAID_LIGHT)

    # Braces: down the front and back, and over the shoulders
    for face in ("torso_front", "torso_back"):
        for left in (26, 78):
            stripe(draw, face, HI_VIS, left, 24)
            stripe(draw, face, HI_VIS_DEEP, left, 3)
            stripe(draw, face, HI_VIS_DEEP, left + 21, 3)
    for left in (26, 78):
        stripe(draw, "torso_up", HI_VIS, left, 24)
    # Buckles where the braces meet the waistband
    band(draw, "torso_front", LEATHER, 104, 20)
    band(draw, "torso_back", LEATHER, 104, 20)
    for face in ("torso_left", "torso_right"):
        band(draw, face, LEATHER, 104, 20)
    stripe(draw, "torso_front", BRASS, 54, 20, top=107, height=14)

    # Rolled cuffs at the wrist
    for face in LIMB_SIDES:
        band(draw, face, CUFF, 100, 28)
    for face in LIMB_BOTTOMS:
        fill(draw, face, CUFF)

    return image


def build_mira_pants():
    image = sheet(HI_VIS)
    draw = ImageDraw.Draw(image)

    for face in TORSO_FACES + LIMB_FACES:
        fill(draw, face, HI_VIS)

    # Tool belt round the waist, with pouches on the front
    for face in ("torso_front", "torso_back", "torso_left", "torso_right"):
        band(draw, face, LEATHER, 0, 22)
    fill(draw, "torso_up", LEATHER)
    stripe(draw, "torso_front", BRASS, 54, 20, top=2, height=18)
    for left in (14, 84):
        stripe(draw, "torso_front", LEATHER, left, 30, top=22, height=26)

    # Knee seams, so the leg is not a flat slab of yellow
    for face in LIMB_SIDES:
        band(draw, face, HI_VIS_DEEP, 62, 4)
        band(draw, face, HI_VIS_DEEP, 108, 6)

    return image


# ---------------------------------------------------------------------------
# Bront - mason: hi-vis vest over a dark shirt, denim jeans
# ---------------------------------------------------------------------------

WORK_NAVY = (46, 54, 72)
WORK_NAVY_DARK = (32, 38, 52)
REFLECT = (238, 240, 236)
DENIM = (52, 72, 116)
DENIM_DARK = (38, 54, 88)
DENIM_SEAM = (150, 162, 190)


def build_bront_shirt():
    image = sheet(WORK_NAVY)
    draw = ImageDraw.Draw(image)

    for face in TORSO_FACES + LIMB_FACES:
        fill(draw, face, WORK_NAVY)

    # The vest: yellow over the torso, open down the middle at the front
    for face in ("torso_back", "torso_left", "torso_right"):
        fill(draw, face, HI_VIS)
    fill(draw, "torso_front", HI_VIS)
    stripe(draw, "torso_front", WORK_NAVY, 56, 16)
    fill(draw, "torso_up", HI_VIS)

    # Reflective stripes: two down the front and back, one round the middle
    for face in ("torso_front", "torso_back"):
        for left in (28, 84):
            stripe(draw, face, REFLECT, left, 16)
        band(draw, face, REFLECT, 74, 14)
    for face in ("torso_left", "torso_right"):
        band(draw, face, REFLECT, 74, 14)
        stripe(draw, face, REFLECT, 24, 16)

    # Collar and the shirt showing at the neck
    band(draw, "torso_front", WORK_NAVY_DARK, 0, 10)
    band(draw, "torso_back", WORK_NAVY_DARK, 0, 10)

    # Sleeves stay dark, with a cuff seam
    for face in LIMB_SIDES:
        band(draw, face, WORK_NAVY_DARK, 112, 16)

    return image


def build_bront_pants():
    image = sheet(DENIM)
    draw = ImageDraw.Draw(image)

    for face in TORSO_FACES + LIMB_FACES:
        fill(draw, face, DENIM)

    # Waistband and a big buckle
    for face in ("torso_front", "torso_back", "torso_left", "torso_right"):
        band(draw, face, LEATHER, 0, 20)
    fill(draw, "torso_up", LEATHER)
    stripe(draw, "torso_front", BRASS, 52, 24, top=1, height=18)

    # Denim seams down the outside of each leg, and turn-ups at the ankle
    for face in ("limbA_outer", "limbB_outer"):
        stripe(draw, face, DENIM_SEAM, 4, 3)
        stripe(draw, face, DENIM_SEAM, 57, 3)
    for face in LIMB_SIDES:
        band(draw, face, DENIM_DARK, 110, 18)
    for face in LIMB_BOTTOMS:
        fill(draw, face, DENIM_DARK)

    return image


# ---------------------------------------------------------------------------
# Elrik - smith: leather apron over rolled linen sleeves, dark trousers
# ---------------------------------------------------------------------------

LINEN = (238, 236, 228)
LINEN_SHADE = (206, 202, 190)
APRON = (74, 56, 40)
APRON_DARK = (52, 38, 26)
APRON_EDGE = (96, 74, 52)
TROUSER = (58, 58, 60)


def build_elrik_shirt():
    image = sheet(LINEN)
    draw = ImageDraw.Draw(image)

    for face in TORSO_FACES + LIMB_FACES:
        fill(draw, face, LINEN)

    # Apron across the front, narrower at the chest, with the straps going
    # over the shoulders and a belt round the middle
    fill(draw, "torso_front", LINEN)
    draw.rectangle(
        [REGIONS["torso_front"][0] + 18, REGIONS["torso_front"][1] + 6,
         REGIONS["torso_front"][0] + 109, REGIONS["torso_front"][1] + 127],
        fill=APRON,
    )
    draw.rectangle(
        [REGIONS["torso_front"][0] + 34, REGIONS["torso_front"][1],
         REGIONS["torso_front"][0] + 93, REGIONS["torso_front"][1] + 40],
        fill=APRON,
    )
    band(draw, "torso_front", APRON_DARK, 62, 12)
    band(draw, "torso_front", APRON_EDGE, 58, 3)
    stripe(draw, "torso_front", BRASS, 56, 16, top=60, height=16)

    for left in (30, 82):
        stripe(draw, "torso_up", APRON, left, 16)
        stripe(draw, "torso_back", APRON, left, 16, top=0, height=54)

    # A hint of shade at the sides so the linen is not a flat white slab
    for face in ("torso_left", "torso_right"):
        stripe(draw, face, LINEN_SHADE, 0, 8)

    return image


def build_elrik_pants():
    image = sheet(TROUSER)
    draw = ImageDraw.Draw(image)

    for face in TORSO_FACES + LIMB_FACES:
        fill(draw, face, TROUSER)

    # The apron carries on down the front of the legs
    for face in ("torso_front",):
        fill(draw, face, APRON)
    stripe(draw, "limbA_front", APRON, 6, 52)
    stripe(draw, "limbB_front", APRON, 6, 52)
    for face in ("limbA_front", "limbB_front"):
        band(draw, face, TROUSER, 96, 32)

    for face in ("torso_front", "torso_back", "torso_left", "torso_right"):
        band(draw, face, APRON_DARK, 0, 14)

    return image


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

SKIN = {"mira": (240, 200, 168), "bront": (226, 178, 140), "elrik": (238, 200, 166)}


def preview(name, shirt, pants):
    """
    What the front of the figure will look like: the faces that face you,
    laid out at R6 proportions. Judging clothing from the flat template is
    guesswork; this is the thing you actually see in game.
    """
    pad, gap = 24, 4
    width = pad * 2 + 64 + gap + 128 + gap + 64
    height = pad * 2 + 64 + gap + 128 + gap + 128
    image = Image.new("RGB", (width, height), (232, 234, 236))

    torso_x = pad + 64 + gap
    head_y = pad
    torso_y = head_y + 64 + gap
    leg_y = torso_y + 128 + gap

    # Head, in skin: the face and hair are accessories, not clothing
    image.paste(Image.new("RGB", (128, 64), SKIN[name]), (torso_x, head_y))

    def face(source, region, box):
        x, y, w, h = REGIONS[region]
        image.paste(source.crop((x, y, x + w, y + h)), box)

    face(shirt, "torso_front", (torso_x, torso_y))
    face(shirt, "limbA_front", (pad, torso_y))
    face(shirt, "limbB_front", (torso_x + 128 + gap, torso_y))
    face(pants, "limbA_front", (torso_x, leg_y))
    face(pants, "limbB_front", (torso_x + 64, leg_y))

    return image


BUILDS = (
    ("mira_shirt.png", build_mira_shirt),
    ("mira_pants.png", build_mira_pants),
    ("bront_shirt.png", build_bront_shirt),
    ("bront_pants.png", build_bront_pants),
    ("elrik_shirt.png", build_elrik_shirt),
    ("elrik_pants.png", build_elrik_pants),
)


def main():
    made = {}
    for name, build in BUILDS:
        image = build()
        made[name] = image
        save(image, name)

    for trader in ("mira", "bront", "elrik"):
        save(preview(trader, made[f"{trader}_shirt.png"], made[f"{trader}_pants.png"]), f"{trader}_preview.png")


main()

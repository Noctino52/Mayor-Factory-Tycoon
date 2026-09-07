"""
Sell zones - the working pitches of Mira, Bront and Elrik, for Mayor's
Factory Tycoon.

Run headless:
    blender --background --python modeling/sellzones.py

Outputs, one set per trader:
    modeling/renders/<name>stall_<view>.png   previews to judge the shape
    modeling/export/<name>stall.fbx           import these into Studio

Conventions:
    1 Blender unit = 1 Roblox stud, one 8-stud cell (+/-4.0 on X and Y).
    Modelled Z-up; the exporter converts to Roblox's Y-up.
    -Y is the customer side. The trade goes on across a bench at Y = +0.2,
    and the trader stands behind it at Y = +1.5 facing the front, which is
    where PlotNPCs puts them (Roblox Z = -Y, so that is Z = -1.5 in game).

Groups (kept out of the static merge, because the game reads them back):
    <Name>StallPad_*   the deck they stand on - PlotNPCs measures its top to
                       know how high the trader's feet go
Everything else merges into <Name>Stall_*.
"""

import math
import os

import bpy

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RENDER_DIR = os.path.join(SCRIPT_DIR, "renders")
EXPORT_DIR = os.path.join(SCRIPT_DIR, "export")

CELL_HALF = 4.0  # a placed zone may not cross this on X or Y

PAD_TOP = 0.16    # the deck everyone stands on
BENCH_TOP = 1.05  # working height, the same for all three trades

# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            block.remove(item)


def material(name, color, metallic=0.0, roughness=0.45, emission=None):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.5
    return mat


def _finish(obj, mat, bevel_width, segments):
    """Apply scale (so bevel width stays uniform), bevel the hard edges."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)

    if bevel_width > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel_width
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        mod.harden_normals = True

    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def box(name, size, location, mat, rotation=(0, 0, 0), bevel=0.022, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    return _finish(obj, mat, bevel, segments)


def cylinder(name, radius, depth, location, mat, rotation=(0, 0, 0), verts=20, bevel=0.012):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, bevel, 1)


def wedge(name, size, location, mat, rotation=(0, 0, 0)):
    """A ramp: a cube with its top edge pulled to one side."""
    obj = box(name, size, location, mat, rotation=rotation, bevel=0)
    mesh = obj.data
    for vertex in mesh.vertices:
        if vertex.co.z > 0:
            vertex.co.y = -0.5
    return obj


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

MAT = {}


def build_materials():
    # One deck under all three, so a sell zone reads as a sell zone; the trade
    # shows in the furniture and in the colour of the kerb around it.
    MAT["deck"] = material("Deck", (0.30, 0.28, 0.25), 0.0, 0.74)
    MAT["timber"] = material("Timber", (0.60, 0.40, 0.20), 0.0, 0.60)
    MAT["bark"] = material("Bark", (0.19, 0.11, 0.06), 0.0, 0.74)
    MAT["stone"] = material("Stone", (0.44, 0.45, 0.46), 0.0, 0.64)
    MAT["stone_dark"] = material("StoneDark", (0.20, 0.21, 0.22), 0.0, 0.70)
    MAT["brick"] = material("Brick", (0.50, 0.22, 0.14), 0.0, 0.64)
    MAT["mortar"] = material("Mortar", (0.74, 0.73, 0.68), 0.0, 0.78)
    MAT["iron"] = material("Iron", (0.26, 0.27, 0.29), 0.80, 0.36)
    MAT["steel"] = material("Steel", (0.52, 0.55, 0.58), 0.85, 0.28)
    MAT["coal"] = material("Coal", (0.05, 0.05, 0.06), 0.0, 0.82)
    MAT["ember"] = material("Ember", (0.95, 0.32, 0.05), 0.0, 0.40, emission=(1.0, 0.34, 0.04))


# ---------------------------------------------------------------------------
# Shared furniture
# ---------------------------------------------------------------------------


def build_pad(rim):
    """
    The deck the zone occupies. Named Pad* so it merges into its own group:
    the game measures its top to know where the trader's feet go, and the
    bounding box would otherwise report the roof.
    """
    box("PadDeck", (7.50, 7.50, PAD_TOP - 0.04), (0, 0, (PAD_TOP - 0.04) / 2), MAT["deck"], bevel=0.03)
    box("PadRim", (7.80, 7.80, 0.06), (0, 0, 0.03), rim, bevel=0.02)

    # A kerb along the customer side, so it reads as a pitch and not a slab
    for index, x in enumerate((-2.20, 0.0, 2.20)):
        box(f"PadKerb{index}", (1.60, 0.26, 0.14), (x, -3.58, PAD_TOP + 0.03), rim, bevel=0.03)


def build_bench(top_mat, leg_mat, width=3.20, depth=1.10, x=0.0):
    """The working surface the trade happens over, at the same height for all."""
    box("BenchTop", (width, depth, 0.18), (x, 0.20, BENCH_TOP - 0.09), top_mat, bevel=0.025)
    for index, (lx, ly) in enumerate((
        (x - width / 2 + 0.22, 0.20 - depth / 2 + 0.18),
        (x + width / 2 - 0.22, 0.20 - depth / 2 + 0.18),
        (x - width / 2 + 0.22, 0.20 + depth / 2 - 0.18),
        (x + width / 2 - 0.22, 0.20 + depth / 2 - 0.18),
    )):
        box(f"BenchLeg{index}", (0.20, 0.20, BENCH_TOP - 0.18 - PAD_TOP), (lx, ly, PAD_TOP + (BENCH_TOP - 0.18 - PAD_TOP) / 2), leg_mat, bevel=0.02)
    box("BenchRail", (width - 0.30, 0.14, 0.14), (x, 0.20, PAD_TOP + 0.30), leg_mat, bevel=0.02)


def build_sign(post_mat, board_mat, mark_mat):
    """
    A trade sign on a post at the front corner - deliberately small and out
    at the edge, because the bench behind it is the thing worth looking at.
    """
    box("SignPost", (0.18, 0.18, 1.70), (-3.05, -3.00, PAD_TOP + 0.85), post_mat, bevel=0.02)
    box("SignBoard", (1.20, 0.10, 0.56), (-3.05, -3.06, PAD_TOP + 1.52), board_mat, bevel=0.03)
    box("SignMark", (0.72, 0.05, 0.14), (-3.05, -3.12, PAD_TOP + 1.52), mark_mat, bevel=0.02)


# ---------------------------------------------------------------------------
# Mira, the carpenter
# ---------------------------------------------------------------------------


def build_mira():
    build_pad(MAT["bark"])

    # Open shed: a board wall at the back under a lean-to of planks
    for index in range(9):
        x = -3.20 + index * 0.80
        box(f"WallBoard{index}", (0.74, 0.16, 2.60), (x, 3.30, PAD_TOP + 1.30), MAT["timber"], bevel=0.02)
    box("WallBeam", (7.20, 0.24, 0.22), (0, 3.30, PAD_TOP + 2.70), MAT["bark"], bevel=0.025)

    for index, x in enumerate((-3.20, 3.20)):
        box(f"RoofPost{index}", (0.26, 0.26, 2.30), (x, 0.60, PAD_TOP + 1.15), MAT["bark"], bevel=0.025)
    for index in range(7):
        y = 0.40 + index * 0.50
        lift = 0.30 * index / 6.0
        box(
            f"RoofPlank{index}",
            (7.00, 0.48, 0.10),
            (0, y, PAD_TOP + 2.32 + lift),
            MAT["timber"],
            rotation=(math.radians(-4.5), 0, 0),
            bevel=0.02,
        )

    build_bench(MAT["timber"], MAT["bark"], width=3.40, depth=1.20, x=-1.10)

    # Work in progress on the bench: boards clamped, a mallet, offcuts
    for index in range(3):
        box(f"BenchPlank{index}", (2.60, 0.44, 0.12), (-1.10, -0.05 + index * 0.02, BENCH_TOP + 0.06 + index * 0.13), MAT["timber"], bevel=0.02)
    box("BenchClamp", (0.18, 0.70, 0.40), (0.20, 0.20, BENCH_TOP + 0.20), MAT["iron"], bevel=0.02)
    cylinder("MalletHandle", 0.06, 0.60, (-2.30, 0.55, BENCH_TOP + 0.09), MAT["bark"], rotation=(0, math.radians(90), 0))
    cylinder("MalletHead", 0.16, 0.34, (-2.62, 0.55, BENCH_TOP + 0.09), MAT["timber"], rotation=(0, math.radians(90), 0))

    # Sawhorses and a stack of finished boards on the far side
    for index, y in enumerate((0.10, 1.30)):
        box(f"HorseBeam{index}", (1.90, 0.18, 0.16), (2.20, y, PAD_TOP + 0.86), MAT["bark"], bevel=0.02)
        for leg, (lx, ly) in enumerate(((1.50, y - 0.30), (2.90, y - 0.30), (1.50, y + 0.30), (2.90, y + 0.30))):
            box(f"HorseLeg{index}{leg}", (0.12, 0.12, 0.86), (lx, ly, PAD_TOP + 0.43), MAT["bark"], bevel=0.015)
    for index in range(5):
        box(f"StackBoard{index}", (1.80, 1.30, 0.14), (2.20, 0.70, PAD_TOP + 1.02 + index * 0.15), MAT["timber"], bevel=0.02)

    # Logs waiting to be worked, against the back wall
    for index, x in enumerate((-2.90, -2.20, -2.55)):
        cylinder(
            f"YardLog{index}",
            0.34,
            2.00,
            (x, 2.55, PAD_TOP + 0.34 + (0.58 if index == 2 else 0)),
            MAT["bark"],
            rotation=(0, math.radians(90), 0),
            verts=14,
        )

    build_sign(MAT["bark"], MAT["timber"], MAT["steel"])


# ---------------------------------------------------------------------------
# Bront, the mason
# ---------------------------------------------------------------------------


def build_bront():
    build_pad(MAT["brick"])

    # A wall going up at the back, the top course still unfinished
    for course in range(6):
        z = PAD_TOP + 0.16 + course * 0.30
        offset = 0.0 if course % 2 == 0 else 0.42
        count = 8 if course < 5 else 5
        first, last = None, None
        for index in range(count):
            x = -3.20 + offset + index * 0.84
            if x > 3.30:
                continue
            box(f"WallBrick{course}{index}", (0.78, 0.42, 0.26), (x, 3.20, z), MAT["brick"], bevel=0.02)
            first = first if first is not None else x
            last = x

        # The mortar bed stops where the course does, or the top of a wall
        # that is still going up would have a metre of it hanging in the air
        if first is not None:
            width = (last - first) + 0.78
            box(f"WallMortar{course}", (width, 0.44, 0.05), ((first + last) / 2, 3.20, z + 0.15), MAT["mortar"], bevel=0.01)

    build_bench(MAT["stone"], MAT["stone_dark"], width=3.00, depth=1.10, x=1.20)

    # Mortar board and a tub of mix on the bench
    box("MortarBoard", (1.60, 0.80, 0.08), (1.20, 0.20, BENCH_TOP + 0.04), MAT["timber"], bevel=0.02)
    box("MortarHeap", (0.90, 0.50, 0.16), (1.20, 0.20, BENCH_TOP + 0.14), MAT["mortar"], bevel=0.06)
    cylinder("MixTub", 0.42, 0.50, (2.60, 0.40, BENCH_TOP + 0.16), MAT["stone_dark"], verts=16)
    cylinder("MixContents", 0.34, 0.10, (2.60, 0.40, BENCH_TOP + 0.38), MAT["mortar"], verts=16)

    # Stacked bricks and blocks on the other side
    for layer in range(4):
        for index in range(3):
            box(
                f"BrickStack{layer}{index}",
                (0.80, 0.44, 0.26),
                (-2.60 + index * 0.86 if layer % 2 == 0 else -2.40 + index * 0.86, 1.30, PAD_TOP + 0.13 + layer * 0.28),
                MAT["brick"],
                bevel=0.02,
            )
    for index, x in enumerate((-2.90, -1.90)):
        box(f"BlockStack{index}", (0.90, 0.90, 0.60), (x, 2.50, PAD_TOP + 0.30), MAT["stone"], bevel=0.03)
        box(f"BlockStackTop{index}", (0.90, 0.90, 0.60), (x, 2.50, PAD_TOP + 0.90), MAT["stone"], bevel=0.03)

    # Wheelbarrow parked at the front
    box("BarrowTray", (1.30, 0.90, 0.42), (2.50, -1.70, PAD_TOP + 0.55), MAT["iron"], bevel=0.03)
    for index, x in enumerate((1.90, 3.10)):
        box(f"BarrowHandle{index}", (0.10, 1.90, 0.10), (x, -2.40, PAD_TOP + 0.62), MAT["timber"], bevel=0.02)
        box(f"BarrowLeg{index}", (0.10, 0.10, 0.34), (x, -1.40, PAD_TOP + 0.17), MAT["iron"], bevel=0.02)
    cylinder("BarrowWheel", 0.30, 0.14, (2.50, -1.00, PAD_TOP + 0.30), MAT["stone_dark"], rotation=(0, math.radians(90), 0), verts=16)

    build_sign(MAT["stone_dark"], MAT["stone"], MAT["brick"])


# ---------------------------------------------------------------------------
# Elrik, the smith
# ---------------------------------------------------------------------------


def build_elrik():
    build_pad(MAT["iron"])

    # Stone forge with a hood and chimney at the back
    box("ForgeBody", (2.60, 1.60, 1.10), (-1.60, 2.70, PAD_TOP + 0.55), MAT["stone"], bevel=0.03)
    box("ForgeHearth", (1.90, 1.10, 0.14), (-1.60, 2.60, PAD_TOP + 1.10), MAT["coal"], bevel=0.02)
    box("ForgeCoals", (1.50, 0.80, 0.12), (-1.60, 2.60, PAD_TOP + 1.20), MAT["ember"], bevel=0.03)
    for index, x in enumerate((-2.72, -0.48)):
        box(f"ForgeHoodPost{index}", (0.18, 0.18, 0.70), (x, 2.90, PAD_TOP + 1.45), MAT["iron"], bevel=0.02)
    box("ForgeHood", (2.40, 1.40, 0.60), (-1.60, 2.90, PAD_TOP + 1.80), MAT["iron"], bevel=0.04)
    box("ForgeHoodLip", (2.56, 1.52, 0.10), (-1.60, 2.90, PAD_TOP + 1.54), MAT["iron"], bevel=0.03)
    box("ForgeChimney", (0.80, 0.80, 1.60), (-1.60, 3.10, PAD_TOP + 2.60), MAT["stone"], bevel=0.03)
    box("ForgeCap", (1.00, 1.00, 0.14), (-1.60, 3.10, PAD_TOP + 3.42), MAT["iron"], bevel=0.02)

    # Bellows on the side of the forge
    box("BellowsBoard", (0.90, 1.10, 0.12), (-3.10, 2.30, PAD_TOP + 0.90), MAT["timber"], bevel=0.02)
    box("BellowsBag", (0.80, 0.90, 0.34), (-3.10, 2.30, PAD_TOP + 0.70), MAT["bark"], bevel=0.06)

    # The anvil on its stump, where the work actually happens
    cylinder("AnvilStump", 0.46, BENCH_TOP - PAD_TOP - 0.30, (0.10, 0.20, PAD_TOP + (BENCH_TOP - PAD_TOP - 0.30) / 2), MAT["bark"], verts=14)
    box("AnvilBase", (1.10, 0.62, 0.16), (0.10, 0.20, BENCH_TOP - 0.22), MAT["iron"], bevel=0.03)
    box("AnvilWaist", (0.60, 0.44, 0.20), (0.10, 0.20, BENCH_TOP - 0.04), MAT["iron"], bevel=0.03)
    box("AnvilFace", (1.60, 0.56, 0.22), (0.10, 0.20, BENCH_TOP + 0.17), MAT["iron"], bevel=0.03)
    box("AnvilHorn", (0.60, 0.34, 0.18), (1.10, 0.20, BENCH_TOP + 0.17), MAT["iron"], bevel=0.06)
    box("AnvilWork", (0.70, 0.20, 0.08), (0.10, 0.20, BENCH_TOP + 0.32), MAT["ember"], bevel=0.02)

    # Quench barrel and a rack of tools
    cylinder("QuenchBarrel", 0.50, 0.90, (2.60, 1.40, PAD_TOP + 0.45), MAT["bark"], verts=16)
    for index, z in enumerate((PAD_TOP + 0.22, PAD_TOP + 0.68)):
        cylinder(f"QuenchHoop{index}", 0.53, 0.08, (2.60, 1.40, z), MAT["iron"], verts=16)
    cylinder("QuenchWater", 0.42, 0.06, (2.60, 1.40, PAD_TOP + 0.88), MAT["steel"], verts=16)

    box("RackPostL", (0.16, 0.16, 1.90), (2.10, 2.90, PAD_TOP + 0.95), MAT["timber"], bevel=0.02)
    box("RackPostR", (0.16, 0.16, 1.90), (3.40, 2.90, PAD_TOP + 0.95), MAT["timber"], bevel=0.02)
    box("RackBar", (1.50, 0.12, 0.12), (2.75, 2.90, PAD_TOP + 1.80), MAT["iron"], bevel=0.02)
    for index, x in enumerate((2.35, 2.75, 3.15)):
        box(f"RackTool{index}", (0.10, 0.10, 0.80), (x, 2.90, PAD_TOP + 1.34), MAT["iron"], bevel=0.02)
        box(f"RackHead{index}", (0.24, 0.16, 0.20), (x, 2.90, PAD_TOP + 0.98), MAT["steel"], bevel=0.02)

    # Finished bars stacked on a low stand, ready to go
    box("BarStand", (1.20, 0.80, 0.14), (1.90, 0.30, PAD_TOP + 0.40), MAT["bark"], bevel=0.02)
    for index, x in enumerate((1.60, 1.90, 2.20)):
        box(f"BarLegOf{index}", (0.12, 0.12, 0.40), (x, 0.30, PAD_TOP + 0.20), MAT["bark"], bevel=0.02)
    for layer in range(3):
        for index in range(2):
            box(
                f"IronBar{layer}{index}",
                (0.90, 0.18, 0.12),
                (1.90, 0.10 + index * 0.26, PAD_TOP + 0.53 + layer * 0.14),
                MAT["steel"],
                bevel=0.02,
            )

    # Coal heap by the forge
    for index, (x, y, size) in enumerate(((-3.20, 1.20, 0.70), (-2.60, 1.00, 0.52), (-3.00, 0.70, 0.40))):
        box(f"CoalHeap{index}", (size, size, size * 0.7), (x, y, PAD_TOP + size * 0.35), MAT["coal"], bevel=0.08)

    build_sign(MAT["iron"], MAT["stone_dark"], MAT["ember"])


# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------


def setup_lighting():
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.66, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.1
    bpy.context.scene.world = world

    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 900
    key.size = 6
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (5.0, -5.5, 6.5)
    key_obj.rotation_euler = (math.radians(42), 0, math.radians(42))
    bpy.context.scene.collection.objects.link(key_obj)

    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 320
    fill.size = 8
    fill_obj = bpy.data.objects.new("Fill", fill)
    fill_obj.location = (-6.0, -3.0, 4.0)
    fill_obj.rotation_euler = (math.radians(62), 0, math.radians(-58))
    bpy.context.scene.collection.objects.link(fill_obj)

    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.01))
    ground = bpy.context.active_object
    ground.name = "Ground"
    ground.data.materials.append(material("Ground", (0.28, 0.34, 0.22), 0.0, 0.85))


def setup_camera():
    target = bpy.data.objects.new("CamTarget", None)
    target.location = (0, 0.4, 1.3)
    bpy.context.scene.collection.objects.link(target)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    track = cam.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    return cam


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"


VIEWS = {
    "hero": (8.6, -9.4, 5.6),
    "front": (0.2, -11.0, 3.4),
}


def render_views(cam, name):
    os.makedirs(RENDER_DIR, exist_ok=True)
    for view, location in VIEWS.items():
        cam.location = location
        bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"{name}stall_{view}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[render] {name} {view}")


def report_stats(name):
    from mathutils import Vector

    depsgraph = bpy.context.evaluated_depsgraph_get()
    triangles = 0
    objects = 0
    worst_object = ("", 0)
    min_corner = [1e9, 1e9, 1e9]
    max_corner = [-1e9, -1e9, -1e9]
    pad_top = None

    for obj in bpy.context.scene.objects:
        if obj.type not in {"MESH", "CURVE"} or obj.name == "Ground":
            continue

        objects += 1
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        count = len(mesh.loop_triangles)
        triangles += count
        if count > worst_object[1]:
            worst_object = (obj.name, count)
        evaluated.to_mesh_clear()

        for corner in evaluated.bound_box:
            world_corner = evaluated.matrix_world @ Vector(corner)
            for axis in range(3):
                min_corner[axis] = min(min_corner[axis], world_corner[axis])
                max_corner[axis] = max(max_corner[axis], world_corner[axis])
            if obj.name.startswith("Pad"):
                pad_top = max(pad_top or world_corner[2], world_corner[2])

    print(f"\n=== {name} stats ===")
    print(f"objects  : {objects}")
    print(f"triangles: {triangles} total, worst single part {worst_object[0]} at {worst_object[1]}")
    print(f"bounds X : {min_corner[0]:.2f} .. {max_corner[0]:.2f}  (cell limit +/-{CELL_HALF})")
    print(f"bounds Y : {min_corner[1]:.2f} .. {max_corner[1]:.2f}  (cell limit +/-{CELL_HALF})")
    print(f"height   : {max_corner[2]:.2f}   pad top {pad_top:.2f}")
    print(f"centre   : X {(min_corner[0] + max_corner[0]) / 2:+.2f}  Y {(min_corner[1] + max_corner[1]) / 2:+.2f}")

    if max(abs(min_corner[0]), abs(max_corner[0]), abs(min_corner[1]), abs(max_corner[1])) > CELL_HALF:
        print("WARNING: the model crosses the grid cell boundary")
    if worst_object[1] > 10000:
        print("WARNING: a single part is over the MeshPart triangle budget")


def orient_for_roblox():
    """
    Roblox's FBX import mirrors X relative to how the model is built here.
    A rigid 180-degree turn about Z cancels it, unlike mirroring the geometry
    which would invert the normals. Y ends up negated, which is why the
    trader's -Y side here is +Z in game.
    """
    import mathutils

    turn = mathutils.Matrix.Rotation(math.pi, 4, "Z")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "CURVE"} and obj.name != "Ground":
            obj.matrix_world = turn @ obj.matrix_world


def join_by_material(prefix):
    """
    Collapse the build into one mesh per material, keeping the deck as its
    own group. Every object would otherwise import as its own MeshPart, and a
    hundred parts per zone adds up fast across six players' plots.

    Resulting names are <prefix>_<Material> and <prefix>Pad_<Material>, which
    the game reads back to re-apply colours and to find the standing height.
    """
    bpy.ops.object.select_all(action="DESELECT")

    for obj in list(bpy.context.scene.objects):
        if obj.type == "CURVE":
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.convert(target="MESH")
            obj.select_set(False)

    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or obj.name == "Ground":
            continue
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)

    groups = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or obj.name == "Ground":
            continue
        material_name = obj.data.materials[0].name if obj.data.materials else "Untextured"
        group = f"{prefix}Pad" if obj.name.startswith("Pad") else prefix
        groups.setdefault((group, material_name), []).append(obj)

    for (group, material_name), objects in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        bpy.context.active_object.name = f"{group}_{material_name}"
        bpy.ops.object.select_all(action="DESELECT")

    print(f"[join] {len(groups)} parts after merging")
    for group, material_name in sorted(groups):
        print(f"        {group}_{material_name}")


def export_fbx(name):
    os.makedirs(EXPORT_DIR, exist_ok=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(obj.type in {"MESH", "CURVE"} and obj.name != "Ground")

    path = os.path.join(EXPORT_DIR, f"{name}stall.fbx")
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        bake_space_transform=True,
        use_mesh_modifiers=True,
    )
    print(f"[export] {path}")


STALLS = (
    ("mira", "MiraStall", build_mira),
    ("bront", "BrontStall", build_bront),
    ("elrik", "ElrikStall", build_elrik),
)


def main():
    for name, prefix, build in STALLS:
        clear_scene()
        build_materials()
        build()
        setup_lighting()
        cam = setup_camera()
        setup_render()
        report_stats(prefix)
        render_views(cam, name)
        orient_for_roblox()
        join_by_material(prefix)
        export_fbx(name)


main()

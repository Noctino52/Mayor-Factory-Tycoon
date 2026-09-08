"""
The three traders - Mira, Bront and Elrik - for Mayor's Factory Tycoon.

Run headless:
    blender --background --python modeling/traders.py

Outputs, one set per trader:
    modeling/renders/<name>_<view>.png   previews to judge the figure
    modeling/export/<name>.fbx           import this into Roblox Studio

Conventions:
    1 Blender unit = 1 Roblox stud, built at classic R6 proportions and full
    R6 size (five studs tall). The game scales them down to diorama size.
    Modelled Z-up; the exporter converts to Roblox's Y-up.
    -Y is the front: the face, the buttons and the tools all face that way.

Body groups (each exported separately so the game can still pose them):
    <Name>Head_*  <Name>Torso_*  <Name>ArmL_*  <Name>ArmR_*
    <Name>LegL_*  <Name>LegR_*

    Everything a part carries moves with it: the hat and beard are Head, the
    apron and belt are Torso, a sleeve and its hand are that arm, a boot is
    its leg. Nothing may span two groups or it will tear when they move.
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

# Classic R6, in studs: the game's own proportions, so the traders match the
# lumberjack and the player standing next to them.
LIMB = (1.0, 1.0, 2.0)     # x, y, z
TORSO = (2.0, 1.0, 2.0)
HEAD = (2.0, 1.25, 1.25)

LEG_Z = 1.0                # centre of a leg
TORSO_Z = 3.0
ARM_X = 1.5
HEAD_Z = 4.5

# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            block.remove(item)


def material(name, color, metallic=0.0, roughness=0.55):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def _finish(obj, mat, bevel_width, segments):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)

    if bevel_width > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel_width
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(40)
        mod.harden_normals = True

    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def box(name, size, location, mat, rotation=(0, 0, 0), bevel=0.05, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    return _finish(obj, mat, bevel, segments)


def ball(name, size, location, mat, rotation=(0, 0, 0), segments=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2, radius=0.5, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    return _finish(obj, mat, 0, 1)


def cylinder(name, radius, depth, location, mat, rotation=(0, 0, 0), verts=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, 0.02, 1)


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

MAT = {}


def build_materials():
    MAT["skin_light"] = material("SkinLight", (0.92, 0.72, 0.56))
    MAT["skin_tan"] = material("SkinTan", (0.84, 0.62, 0.44))
    MAT["hair_dark"] = material("HairDark", (0.16, 0.09, 0.05))
    MAT["hair_black"] = material("HairBlack", (0.05, 0.045, 0.05))
    MAT["hair_fair"] = material("HairFair", (0.66, 0.48, 0.18))
    MAT["hi_vis"] = material("HiVis", (0.85, 0.55, 0.05), 0.0, 0.42)
    MAT["hi_vis_deep"] = material("HiVisDeep", (0.62, 0.38, 0.02), 0.0, 0.42)
    MAT["reflect"] = material("Reflect", (0.92, 0.92, 0.88), 0.10, 0.30)
    MAT["plaid"] = material("Plaid", (0.34, 0.09, 0.07))
    MAT["plaid_dark"] = material("PlaidDark", (0.18, 0.05, 0.04))
    MAT["denim"] = material("Denim", (0.10, 0.16, 0.32))
    MAT["work_navy"] = material("WorkNavy", (0.09, 0.11, 0.16))
    MAT["linen"] = material("Linen", (0.88, 0.86, 0.80))
    MAT["leather"] = material("Leather", (0.19, 0.11, 0.05), 0.0, 0.62)
    MAT["leather_dark"] = material("LeatherDark", (0.09, 0.07, 0.06), 0.0, 0.60)
    MAT["apron_grey"] = material("ApronGrey", (0.17, 0.18, 0.18), 0.0, 0.66)
    MAT["boot"] = material("Boot", (0.12, 0.08, 0.06), 0.0, 0.60)
    MAT["brass"] = material("Brass", (0.62, 0.46, 0.14), 0.70, 0.34)
    MAT["steel"] = material("Steel", (0.52, 0.55, 0.58), 0.85, 0.30)


def cone(name, lower, upper, depth, location, mat, rotation=(0, 0, 0), verts=16):
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=lower, radius2=upper, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, 0.02, 1)


# ---------------------------------------------------------------------------
# The body underneath the clothes
# ---------------------------------------------------------------------------


def build_head(skin):
    """A rounded R6 head. The game puts the face decal on the front of it."""
    box("HeadCore", HEAD, (0, 0, HEAD_Z), skin, bevel=0.16, segments=3)


def build_torso(shirt):
    box("TorsoCore", TORSO, (0, 0, TORSO_Z), shirt, bevel=0.08, segments=2)


def build_arm(side, sleeve, skin, hand_z=2.34):
    """
    One arm and the hand on the end of it. `side` is L or R; the arm keeps
    the R6 footprint so the game's own posing still lands it right.
    """
    x = -ARM_X if side == "L" else ARM_X
    box(f"Arm{side}Sleeve", (1.02, 1.02, 1.42), (x, 0, TORSO_Z + 0.41), sleeve, bevel=0.10)
    box(f"Arm{side}Cuff", (1.06, 1.06, 0.26), (x, 0, TORSO_Z - 0.40), sleeve, bevel=0.08)
    box(f"Arm{side}Hand", (0.82, 0.86, 0.50), (x, -0.02, TORSO_Z - 0.74), skin, bevel=0.20, segments=3)


def build_leg(side, trousers, boot):
    x = -0.5 if side == "L" else 0.5
    box(f"Leg{side}Trouser", (1.02, 1.02, 1.44), (x, 0, LEG_Z + 0.28), trousers, bevel=0.07)
    box(f"Leg{side}Boot", (1.06, 1.14, 0.56), (x, -0.06, 0.28), boot, bevel=0.10, segments=3)
    box(f"Leg{side}Sole", (1.10, 1.20, 0.12), (x, -0.06, 0.06), boot, bevel=0.05)


def build_body(skin, shirt, sleeve, trousers, boot):
    build_head(skin)
    build_torso(shirt)
    build_arm("L", sleeve, skin)
    build_arm("R", sleeve, skin)
    build_leg("L", trousers, boot)
    build_leg("R", trousers, boot)


# ---------------------------------------------------------------------------
# Shared kit
# ---------------------------------------------------------------------------


def build_hard_hat(shell, trim):
    """
    A builder's hard hat: a shallow dome with the brim under it and a peak
    over the eyes. The brim sits above the brow so the face still shows -
    a dome pushed down over it reads as a helmet, not a hat.

    Everything here is sized against HEAD, which is two studs wide. A kit
    drawn for a wider head swallows this one whole.
    """
    ball("HeadHelmetShell", (2.10, 1.94, 1.10), (0, 0, HEAD_Z + 0.66), shell, segments=26)
    cylinder("HeadHelmetBrim", 1.24, 0.09, (0, -0.05, HEAD_Z + 0.55), shell, verts=28)
    box("HeadHelmetPeak", (1.22, 0.76, 0.11), (0, -1.14, HEAD_Z + 0.57), shell,
        rotation=(math.radians(-12), 0, 0), bevel=0.05)
    box("HeadHelmetRidge", (0.30, 1.16, 0.16), (0, 0, HEAD_Z + 1.12), trim, bevel=0.06)
    for index, x in enumerate((-0.58, 0.58)):
        box(f"HeadHelmetVent{index}", (0.12, 0.80, 0.11), (x, 0, HEAD_Z + 1.05), trim, bevel=0.04)


def build_beard(colour, point_depth=0.52, moustache=True):
    """
    Round the jaw, never across the eyes: a mass over the chin, sideburns
    at the cheeks, and a tapered point below. A block over the front of the
    head hides the face, which is what makes a figure look like a brick.
    """
    ball("HeadBeardMass", (1.88, 1.24, 1.10), (0, -0.32, HEAD_Z - 0.38), colour, segments=22)
    for index, x in enumerate((-0.84, 0.84)):
        ball(f"HeadBeardCheek{index}", (0.46, 0.96, 1.00), (x, -0.10, HEAD_Z - 0.08), colour, segments=16)
    cone("HeadBeardPoint", 0.40, 0.08, point_depth, (0, -0.36, HEAD_Z - 0.82 - point_depth / 2), colour,
         rotation=(math.radians(180), 0, 0))
    if moustache:
        ball("HeadMoustache", (0.98, 0.36, 0.26), (0, -0.56, HEAD_Z - 0.06), colour, segments=16)


def build_long_hair(colour, tie):
    """Shoulder-length hair with a plait, all rounded: hair has no flat faces."""
    ball("HeadHairCrown", (2.32, 1.82, 1.24), (0, 0.20, HEAD_Z + 0.40), colour, segments=26)
    ball("HeadHairBack", (2.02, 1.00, 1.84), (0, 0.74, HEAD_Z - 0.38), colour, segments=22)
    for index, x in enumerate((-0.96, 0.96)):
        ball(f"HeadHairSide{index}", (0.52, 1.30, 1.74), (x, 0.12, HEAD_Z - 0.36), colour, segments=18)
    cone("HeadPlait", 0.36, 0.12, 1.14, (0, 0.88, HEAD_Z - 1.36), colour, rotation=(math.radians(180), 0, 0))
    cylinder("HeadPlaitTie", 0.30, 0.14, (0, 0.86, HEAD_Z - 0.90), tie, verts=14)


def build_soft_cap(cloth, band):
    """A soft cap with a leather band, the sort a smith works in."""
    ball("HeadCapShell", (2.06, 1.96, 1.02), (0, 0.05, HEAD_Z + 0.57), cloth, segments=24)
    cylinder("HeadCapBand", 1.05, 0.18, (0, 0.05, HEAD_Z + 0.51), band, verts=26)
    ball("HeadCapStud", (0.26, 0.26, 0.20), (0, 0.05, HEAD_Z + 1.08), band, segments=12)


def build_belt(colour, buckle_mat, buckle_size=(0.56, 0.12, 0.38)):
    box("TorsoBelt", (2.08, 1.08, 0.36), (0, 0, TORSO_Z - 0.86), colour, bevel=0.05)
    box("TorsoBuckle", buckle_size, (0, -0.58, TORSO_Z - 0.86), buckle_mat, bevel=0.05)


# ---------------------------------------------------------------------------
# Mira, the carpenter
# ---------------------------------------------------------------------------


def build_mira():
    build_body(MAT["skin_light"], MAT["plaid"], MAT["plaid"], MAT["hi_vis"], MAT["boot"])

    # Plaid: a couple of darker bands is all that reads as a check at this size
    for index, z in enumerate((TORSO_Z + 0.56, TORSO_Z - 0.30)):
        box(f"TorsoCheck{index}", (2.04, 1.04, 0.18), (0, 0, z), MAT["plaid_dark"], bevel=0.04)
    for side, x in (("L", -ARM_X), ("R", ARM_X)):
        box(f"Arm{side}Check", (1.04, 1.04, 0.16), (x, 0, TORSO_Z + 0.52), MAT["plaid_dark"], bevel=0.04)

    build_long_hair(MAT["hair_dark"], MAT["leather"])

    build_hard_hat(MAT["hi_vis"], MAT["hi_vis_deep"])

    # Hi-vis braces, over the shoulders and buckled at the chest
    for side, x in (("L", -0.56), ("R", 0.56)):
        box(f"TorsoBrace{side}", (0.40, 0.16, 1.94), (x, -0.56, TORSO_Z + 0.06), MAT["hi_vis"], bevel=0.04)
        box(f"TorsoBraceOver{side}", (0.40, 1.06, 0.16), (x, 0, TORSO_Z + 1.00), MAT["hi_vis"], bevel=0.04)
        box(f"TorsoBraceBack{side}", (0.40, 0.16, 1.40), (x, 0.54, TORSO_Z + 0.30), MAT["hi_vis"], bevel=0.04)
        box(f"TorsoBuckle{side}", (0.36, 0.12, 0.34), (x, -0.66, TORSO_Z + 0.52), MAT["leather"], bevel=0.04)

    build_belt(MAT["leather"], MAT["brass"])
    for side, x in (("L", -0.74), ("R", 0.74)):
        box(f"TorsoPouch{side}", (0.60, 0.44, 0.64), (x, -0.56, TORSO_Z - 1.08), MAT["leather"], bevel=0.08)
    box("TorsoRule", (0.20, 0.20, 0.86), (-1.02, -0.28, TORSO_Z - 1.28), material("RuleRed", (0.52, 0.08, 0.06)), rotation=(0, math.radians(8), 0), bevel=0.04)


# ---------------------------------------------------------------------------
# Bront, the mason
# ---------------------------------------------------------------------------


def build_bront():
    build_body(MAT["skin_tan"], MAT["work_navy"], MAT["work_navy"], MAT["denim"], MAT["boot"])

    build_hard_hat(MAT["hi_vis"], MAT["hi_vis_deep"])
    build_beard(MAT["hair_black"])

    # Hi-vis vest, wrapped round the torso and open down the front
    box("TorsoVestBack", (1.94, 0.18, 1.74), (0, 0.54, TORSO_Z - 0.04), MAT["hi_vis"], bevel=0.05)
    for side, x in (("L", -0.68), ("R", 0.68)):
        box(f"TorsoVestFront{side}", (0.58, 0.18, 1.74), (x, -0.56, TORSO_Z - 0.04), MAT["hi_vis"], bevel=0.05)
        box(f"TorsoVestSide{side}", (0.18, 1.10, 1.74), (x * 1.44, 0, TORSO_Z - 0.04), MAT["hi_vis"], bevel=0.05)
        box(f"TorsoVestShoulder{side}", (0.58, 1.06, 0.18), (x, 0, TORSO_Z + 0.94), MAT["hi_vis"], bevel=0.05)
        box(f"TorsoStripe{side}", (0.30, 0.10, 1.74), (x, -0.66, TORSO_Z - 0.04), MAT["reflect"], bevel=0.03)
    box("TorsoStripeBand", (2.00, 0.10, 0.26), (0, -0.66, TORSO_Z - 0.48), MAT["reflect"], bevel=0.03)
    box("TorsoStripeBandBack", (1.96, 0.10, 0.26), (0, 0.64, TORSO_Z - 0.48), MAT["reflect"], bevel=0.03)

    build_belt(MAT["leather"], MAT["brass"], buckle_size=(0.66, 0.14, 0.44))


# ---------------------------------------------------------------------------
# Elrik, the smith
# ---------------------------------------------------------------------------


def build_elrik():
    build_body(MAT["skin_light"], MAT["linen"], MAT["linen"], MAT["work_navy"], MAT["boot"])

    build_soft_cap(MAT["apron_grey"], MAT["leather_dark"])
    build_beard(MAT["hair_fair"], point_depth=0.74)

    # Leather apron: bib, body, and a skirt that carries on over the legs
    box("TorsoApronBib", (1.26, 0.18, 0.96), (0, -0.55, TORSO_Z + 0.74), MAT["apron_grey"], bevel=0.05)
    box("TorsoApronBody", (1.98, 0.20, 1.62), (0, -0.56, TORSO_Z - 0.30), MAT["apron_grey"], bevel=0.05)
    box("TorsoApronBelt", (2.06, 0.28, 0.24), (0, -0.60, TORSO_Z - 0.32), MAT["leather_dark"], bevel=0.05)
    box("TorsoApronBuckle", (0.34, 0.14, 0.30), (0, -0.70, TORSO_Z - 0.32), MAT["brass"], bevel=0.04)
    for side, x in (("L", -0.46), ("R", 0.46)):
        box(f"TorsoStrap{side}", (0.32, 0.18, 1.16), (x, -0.54, TORSO_Z + 0.80), MAT["apron_grey"], rotation=(0, math.radians(6 if side == "L" else -6), 0), bevel=0.04)
        box(f"TorsoStrapOver{side}", (0.32, 1.04, 0.16), (x, 0, TORSO_Z + 1.00), MAT["apron_grey"], bevel=0.04)
        box(f"TorsoStrapBack{side}", (0.32, 0.16, 0.90), (x, 0.52, TORSO_Z + 0.60), MAT["apron_grey"], bevel=0.04)

    # The skirt hangs off the legs, so each half rides with its own leg
    for side, x in (("L", -0.5), ("R", 0.5)):
        box(f"Leg{side}Apron", (1.06, 0.20, 1.20), (x, -0.58, LEG_Z + 0.42), MAT["apron_grey"], bevel=0.05)


# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------


def setup_lighting():
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.66, 0.70, 0.76, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
    bpy.context.scene.world = world

    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 600
    key.size = 5
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (4.0, -5.0, 6.0)
    key_obj.rotation_euler = (math.radians(40), 0, math.radians(38))
    bpy.context.scene.collection.objects.link(key_obj)

    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 220
    fill.size = 6
    fill_obj = bpy.data.objects.new("Fill", fill)
    fill_obj.location = (-5.0, -4.0, 3.0)
    fill_obj.rotation_euler = (math.radians(66), 0, math.radians(-52))
    bpy.context.scene.collection.objects.link(fill_obj)

    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.01))
    ground = bpy.context.active_object
    ground.name = "Ground"
    ground.data.materials.append(material("Ground", (0.30, 0.34, 0.30), 0.0, 0.9))


def setup_camera():
    target = bpy.data.objects.new("CamTarget", None)
    target.location = (0, 0, 2.7)
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
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.image_settings.file_format = "PNG"


VIEWS = {
    "front": (0.0, -14.0, 3.2),
    "three": (7.6, -11.0, 5.0),
}


def render_views(cam, name):
    os.makedirs(RENDER_DIR, exist_ok=True)
    for view, location in VIEWS.items():
        cam.location = location
        bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"{name}_{view}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[render] {name} {view}")


GROUPS = ("Head", "Torso", "ArmL", "ArmR", "LegL", "LegR")


def report_stats(name):
    from mathutils import Vector

    depsgraph = bpy.context.evaluated_depsgraph_get()
    triangles = 0
    per_group = {group: 0 for group in GROUPS}
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]

    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.name == "Ground":
            continue

        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        count = len(mesh.loop_triangles)
        triangles += count
        evaluated.to_mesh_clear()

        group = _group_of(obj.name)
        if group:
            per_group[group] += count
        else:
            print(f"WARNING: {obj.name} belongs to no body group and will not move")

        for corner in evaluated.bound_box:
            world = evaluated.matrix_world @ Vector(corner)
            for axis in range(3):
                lo[axis] = min(lo[axis], world[axis])
                hi[axis] = max(hi[axis], world[axis])

    print(f"\\n=== {name} stats ===")
    print(f"triangles: {triangles} total  " + "  ".join(f"{g} {per_group[g]}" for g in GROUPS))
    print(f"height   : {hi[2] - lo[2]:.2f} studs (R6 is 5.00)")
    print(f"width    : {hi[0] - lo[0]:.2f}   depth {hi[1] - lo[1]:.2f}")


def _group_of(object_name):
    # Longest first, so ArmL is not read as Arm
    for group in sorted(GROUPS, key=len, reverse=True):
        if object_name.startswith(group):
            return group
    return None


def orient_for_roblox():
    """
    Roblox's FBX import mirrors X. A rigid 180-degree turn about Z cancels it
    without inverting normals; Y ends up negated, so the front modelled at -Y
    becomes +Z in game, which is the way a Roblox part faces.
    """
    import mathutils

    turn = mathutils.Matrix.Rotation(math.pi, 4, "Z")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "CURVE"} and obj.name != "Ground":
            obj.matrix_world = turn @ obj.matrix_world


def join_by_group(prefix):
    """
    One mesh per body group and material. The groups have to stay apart: the
    game moves each of them, and anything merged across two would tear.
    """
    bpy.ops.object.select_all(action="DESELECT")

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
        group = _group_of(obj.name)
        if not group:
            continue
        material_name = obj.data.materials[0].name if obj.data.materials else "Untextured"
        groups.setdefault((group, material_name), []).append(obj)

    for (group, material_name), objects in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        bpy.context.active_object.name = f"{prefix}{group}_{material_name}"
        bpy.ops.object.select_all(action="DESELECT")

    print(f"[join] {len(groups)} parts after merging")
    for group, material_name in sorted(groups):
        print(f"        {prefix}{group}_{material_name}")


def export_fbx(name):
    os.makedirs(EXPORT_DIR, exist_ok=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(obj.type == "MESH" and obj.name != "Ground")

    path = os.path.join(EXPORT_DIR, f"{name}.fbx")
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


TRADERS = (
    ("mira", "Mira", build_mira),
    ("bront", "Bront", build_bront),
    ("elrik", "Elrik", build_elrik),
)


def main():
    for name, prefix, build in TRADERS:
        clear_scene()
        build_materials()
        build()
        setup_lighting()
        cam = setup_camera()
        setup_render()
        report_stats(prefix)
        render_views(cam, name)
        orient_for_roblox()
        join_by_group(prefix)
        export_fbx(name)


main()

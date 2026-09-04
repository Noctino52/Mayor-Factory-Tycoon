"""
Sawmill - portable trailer bandsaw mill, for Mayor's Factory Tycoon.

Run headless:
    blender --background --python modeling/sawmill.py

Outputs:
    modeling/renders/sawmill_<view>.png   preview renders to judge the shape
    modeling/export/sawmill.fbx           import this into Roblox Studio

Conventions:
    1 Blender unit = 1 Roblox stud. The machine must fit inside one 8-stud
    grid cell, so nothing may cross +/-4.0 on X or Y.
    Modelled Z-up; the FBX exporter converts to Roblox's Y-up on the way out.
    X is the belt direction: log enters at -X, plank leaves at +X.

    Shape reference: a low, long trailer mill. The saw head is horizontal -
    two big wheel housings with the blade running flat between them - riding
    on vertical guide posts, over a bed of orange log bunks.
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

CELL_HALF = 4.0  # a placed machine may not cross this on X or Y

# Vertical reference points
BED_RAIL_TOP = 0.58   # top of the steel bed frame
BUNK_TOP = 0.86       # where a log actually rests
HEAD_Z = 1.42         # centre line of the horizontal saw head
POST_TOP = 2.30

# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            block.remove(item)


def material(name, color, metallic=0.0, roughness=0.45):
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


def cylinder(name, radius, depth, location, mat, rotation=(0, 0, 0), verts=24, bevel=0.012):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, bevel, 1)


def tube(name, points, radius, mat, resolution=2):
    """A real round tube through the given points - used for hoses and cables."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    curve.fill_mode = "FULL"

    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for index, point in enumerate(points):
        bezier = spline.bezier_points[index]
        bezier.co = point
        bezier.handle_left_type = "AUTO"
        bezier.handle_right_type = "AUTO"

    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

MAT = {}


def build_materials():
    MAT["body_orange"] = material("BodyOrange", (0.80, 0.20, 0.03), 0.30, 0.42)
    MAT["deep_orange"] = material("DeepOrange", (0.55, 0.13, 0.02), 0.30, 0.45)
    MAT["hazard_yellow"] = material("HazardYellow", (0.85, 0.66, 0.06), 0.25, 0.42)
    MAT["galv_steel"] = material("GalvSteel", (0.60, 0.62, 0.64), 0.80, 0.34)
    MAT["dark_metal"] = material("DarkMetal", (0.055, 0.055, 0.065), 0.55, 0.42)
    MAT["steel"] = material("Steel", (0.52, 0.55, 0.58), 0.85, 0.28)
    MAT["blade"] = material("Blade", (0.74, 0.77, 0.80), 0.95, 0.18)
    MAT["white_tank"] = material("WhiteTank", (0.88, 0.88, 0.85), 0.05, 0.40)
    MAT["rubber"] = material("Rubber", (0.035, 0.035, 0.04), 0.0, 0.72)


# ---------------------------------------------------------------------------
# The machine
# ---------------------------------------------------------------------------


def build_bed():
    """Long low galvanised bed frame - the defining shape of a trailer mill."""
    for index, y in enumerate((-0.82, 0.82)):
        box(f"BedRail{index}", (6.40, 0.16, 0.34), (0, y, BED_RAIL_TOP - 0.17), MAT["galv_steel"])

    for index, x in enumerate((-3.05, -2.10, -1.15, -0.20, 0.75, 1.70, 2.65, 3.05)):
        box(f"BedCross{index}", (0.14, 1.80, 0.16), (x, 0, BED_RAIL_TOP - 0.26), MAT["galv_steel"], bevel=0.015)

    # Outriggers: angled legs with pads, like the stabilisers on the real mill
    for index, (x, y) in enumerate(((-2.75, -0.95), (2.75, -0.95), (-2.75, 0.95), (2.75, 0.95))):
        direction = 1 if y > 0 else -1
        box(
            f"Outrigger{index}",
            (0.13, 0.13, 0.70),
            (x, y + direction * 0.16, 0.28),
            MAT["galv_steel"],
            rotation=(direction * math.radians(18), 0, 0),
            bevel=0.015,
        )
        box(f"OutriggerPad{index}", (0.34, 0.34, 0.07), (x, y + direction * 0.34, 0.035), MAT["dark_metal"], bevel=0.015)

    # Trailer wheel tucked under the bed
    cylinder(
        "TrailerWheel",
        0.34,
        0.20,
        (-2.05, -1.02, 0.34),
        MAT["rubber"],
        rotation=(math.radians(90), 0, 0),
        verts=20,
    )
    cylinder(
        "TrailerHub",
        0.13,
        0.23,
        (-2.05, -1.02, 0.34),
        MAT["galv_steel"],
        rotation=(math.radians(90), 0, 0),
        verts=14,
    )
    box("TrailerFender", (0.90, 0.26, 0.10), (-2.05, -1.02, 0.76), MAT["body_orange"], bevel=0.02)


def build_log_bunks():
    """Orange cradles the log sits in, spaced along the bed."""
    for index, x in enumerate((-2.45, -1.05, 1.05, 2.45)):
        # Flat cradle plate the log lies on
        box(f"BunkBase{index}", (0.34, 1.44, 0.18), (x, 0, BUNK_TOP - 0.09), MAT["body_orange"], bevel=0.025)
        # Short upright cheeks that stop it rolling off
        for cheek_index, y in enumerate((-0.66, 0.66)):
            box(
                f"BunkCheek{index}{cheek_index}",
                (0.30, 0.14, 0.30),
                (x, y, BUNK_TOP + 0.06),
                MAT["deep_orange"],
                bevel=0.02,
            )
        # Leg down to the bed frame
        box(f"BunkLeg{index}", (0.16, 0.16, 0.30), (x, 0, BED_RAIL_TOP - 0.02), MAT["galv_steel"], bevel=0.015)


def build_saw_head():
    """
    Horizontal bandsaw head: two big wheel housings with vertical axes and
    the blade running flat between them, carried on two guide posts.
    """
    # Guide posts the head rides on
    for index, x in enumerate((-1.62, 1.62)):
        box(f"GuidePost{index}", (0.20, 0.20, 1.90), (x, -0.62, BED_RAIL_TOP + 0.85), MAT["galv_steel"], bevel=0.02)
        box(f"PostFoot{index}", (0.40, 0.40, 0.10), (x, -0.62, BED_RAIL_TOP + 0.02), MAT["dark_metal"], bevel=0.015)
        # Height crank handle
        cylinder(
            f"CrankShaft{index}",
            0.035,
            0.44,
            (x, -0.90, POST_TOP - 0.20),
            MAT["steel"],
            rotation=(math.radians(90), 0, 0),
            verts=10,
        )

    box("PostTopBar", (3.60, 0.16, 0.16), (0, -0.62, POST_TOP), MAT["galv_steel"], bevel=0.02)

    # Head frame, kept behind the wheels so it never hides them
    box("HeadBeam", (2.40, 0.20, 0.30), (0, 0.30, HEAD_Z + 0.46), MAT["body_orange"], bevel=0.025)
    box("HeadBackPlate", (2.40, 0.14, 0.62), (0, 0.42, HEAD_Z + 0.06), MAT["deep_orange"], bevel=0.02)

    # The two big wheel housings, discs facing the player
    wheel_radius = 0.48
    for index, x in enumerate((-0.90, 0.90)):
        cylinder(
            f"WheelHousing{index}",
            wheel_radius,
            0.24,
            (x, -0.06, HEAD_Z),
            MAT["body_orange"],
            rotation=(math.radians(90), 0, 0),
            verts=28,
            bevel=0.02,
        )
        cylinder(
            f"HousingRing{index}",
            wheel_radius * 0.68,
            0.28,
            (x, -0.08, HEAD_Z),
            MAT["deep_orange"],
            rotation=(math.radians(90), 0, 0),
            verts=24,
            bevel=0.015,
        )
        cylinder(
            f"HousingHub{index}",
            0.11,
            0.34,
            (x, -0.10, HEAD_Z),
            MAT["steel"],
            rotation=(math.radians(90), 0, 0),
            verts=12,
        )

    # The blade: the exposed run between the two housings, at cutting height
    box("BladeRun", (1.80, 0.05, 0.10), (0, -0.06, HEAD_Z - wheel_radius + 0.06), MAT["blade"], bevel=0)
    box("BladeCover", (1.80, 0.26, 0.14), (0, -0.06, HEAD_Z + wheel_radius - 0.02), MAT["dark_metal"], bevel=0.02)

    # Blade guides either side of the cut
    for index, x in enumerate((-0.42, 0.42)):
        box(
            f"BladeGuide{index}",
            (0.16, 0.26, 0.26),
            (x, -0.06, HEAD_Z - wheel_radius + 0.12),
            MAT["dark_metal"],
            bevel=0.02,
        )


def build_powerpack():
    """Engine and fuel tank sitting over the head, like the reference."""
    box("EngineBlock", (0.86, 0.62, 0.52), (0.55, -0.30, POST_TOP + 0.30), MAT["dark_metal"], bevel=0.03)
    box("EngineTop", (0.66, 0.48, 0.12), (0.55, -0.30, POST_TOP + 0.62), MAT["steel"], bevel=0.02)
    cylinder(
        "Exhaust",
        0.075,
        0.34,
        (0.98, -0.56, POST_TOP + 0.62),
        MAT["dark_metal"],
        verts=12,
    )

    box("FuelTank", (0.80, 0.52, 0.34), (-0.62, -0.30, POST_TOP + 0.24), MAT["white_tank"], bevel=0.06)
    cylinder("FuelCap", 0.09, 0.08, (-0.62, -0.30, POST_TOP + 0.45), MAT["dark_metal"], verts=12)

    tube(
        "FuelLine",
        [
            (-0.30, -0.30, POST_TOP + 0.18),
            (0.10, -0.44, POST_TOP + 0.10),
            (0.30, -0.34, POST_TOP + 0.18),
        ],
        0.028,
        MAT["rubber"],
    )

    # Control lever on the near post
    box("ControlBox", (0.24, 0.14, 0.30), (1.62, -0.84, BED_RAIL_TOP + 0.80), MAT["dark_metal"], bevel=0.02)
    cylinder(
        "ControlLever",
        0.03,
        0.34,
        (1.62, -0.94, BED_RAIL_TOP + 1.02),
        MAT["steel"],
        rotation=(math.radians(70), 0, 0),
        verts=10,
    )


def build_flow_markers():
    """
    Infeed ramp (-X) and outfeed table (+X), sized from the game's item sizes
    so it reads which end takes a Log and which end gives back a Plank.
    Log is 0.9 x 0.9 in cross-section, Plank is 0.45 tall x 1.35 wide.
    """
    # Infeed: a pair of loading arms angling up to bunk height
    for index, y in enumerate((-0.55, 0.55)):
        box(
            f"InfeedArm{index}",
            (1.00, 0.16, 0.11),
            (-2.98, y, BUNK_TOP - 0.10),
            MAT["deep_orange"],
            rotation=(0, math.radians(10), 0),
            bevel=0.02,
        )
    box("InfeedStop", (0.12, 1.30, 0.30), (-3.32, 0, BUNK_TOP + 0.02), MAT["hazard_yellow"], bevel=0.02)

    # Outfeed: a flat table the finished plank slides onto, plank-width
    box("OutfeedTable", (1.10, 1.45, 0.10), (3.05, 0, BED_RAIL_TOP + 0.06), MAT["galv_steel"], bevel=0.02)
    for index, y in enumerate((-0.70, 0.70)):
        box(f"OutfeedLip{index}", (1.10, 0.09, 0.20), (3.05, y, BED_RAIL_TOP + 0.16), MAT["hazard_yellow"], bevel=0.02)
        box(f"OutfeedLeg{index}", (0.12, 0.12, 0.44), (3.05, y, 0.22), MAT["galv_steel"], bevel=0.015)


def build_machine():
    build_bed()
    build_log_bunks()
    build_saw_head()
    build_powerpack()
    build_flow_markers()


# ---------------------------------------------------------------------------
# Render + export
# ---------------------------------------------------------------------------


def setup_lighting():
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.66, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.85
    bpy.context.scene.world = world

    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 900
    key.size = 6
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (5.0, -5.5, 6.5)
    key_obj.rotation_euler = (math.radians(48), 0, math.radians(42))
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
    target.location = (0, 0, 1.1)
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
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"


VIEWS = {
    "hero": (6.4, -6.8, 3.6),
    "side": (0.2, -8.4, 1.9),
    "top": (4.2, -4.6, 7.4),
}


def render_views(cam):
    os.makedirs(RENDER_DIR, exist_ok=True)
    for name, location in VIEWS.items():
        cam.location = location
        bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"sawmill_{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[render] {name}")


def report_stats():
    from mathutils import Vector

    depsgraph = bpy.context.evaluated_depsgraph_get()
    triangles = 0
    objects = 0
    worst_object = ("", 0)
    min_corner = [1e9, 1e9, 1e9]
    max_corner = [-1e9, -1e9, -1e9]

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

    print("\n=== Sawmill stats ===")
    print(f"objects  : {objects}")
    print(f"triangles: {triangles} total, worst single part {worst_object[0]} at {worst_object[1]}")
    print(f"bounds X : {min_corner[0]:.2f} .. {max_corner[0]:.2f}  (cell limit +/-{CELL_HALF})")
    print(f"bounds Y : {min_corner[1]:.2f} .. {max_corner[1]:.2f}  (cell limit +/-{CELL_HALF})")
    print(f"height   : {max_corner[2]:.2f}")

    if max(abs(min_corner[0]), abs(max_corner[0]), abs(min_corner[1]), abs(max_corner[1])) > CELL_HALF:
        print("WARNING: the model crosses the grid cell boundary")
    if worst_object[1] > 10000:
        print("WARNING: a single part is over the MeshPart triangle budget")


# Objects belonging to the travelling saw head. They are kept out of the
# static merge so the game can slide the head along the log while it cuts.
HEAD_PREFIXES = (
    "HeadBeam",
    "HeadBackPlate",
    "WheelHousing",
    "HousingRing",
    "HousingHub",
    "BladeRun",
    "BladeCover",
    "BladeGuide",
)


def _group_prefix(obj):
    for prefix in HEAD_PREFIXES:
        if obj.name.startswith(prefix):
            return "SawmillHead"
    return "Sawmill"



def orient_for_roblox():
    """
    Roblox's FBX import mirrors X relative to how the model is built here.
    A rigid 180-degree turn about Z cancels it, unlike mirroring the geometry
    which would invert the normals. Z ends up negated, which is harmless as
    both models are symmetric across the belt line.
    """
    import mathutils

    turn = mathutils.Matrix.Rotation(math.pi, 4, "Z")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "CURVE"} and obj.name != "Ground":
            obj.matrix_world = turn @ obj.matrix_world


def join_by_material():
    """
    Collapse the build into one mesh per material, but keep the saw head as
    its own set of parts so it stays animatable. Every object would otherwise
    import as its own MeshPart, and a hundred parts per machine adds up fast
    across six players' plots.

    Resulting names are Sawmill_<Material> and SawmillHead_<Material>, which
    the game reads back to re-apply colours after import.
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
        groups.setdefault((_group_prefix(obj), material_name), []).append(obj)

    for (prefix, material_name), objects in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        bpy.context.active_object.name = f"{prefix}_{material_name}"
        bpy.ops.object.select_all(action="DESELECT")

    print(f"[join] {len(groups)} parts after merging")
    for prefix, material_name in sorted(groups):
        print(f"        {prefix}_{material_name}")


def export_fbx():
    os.makedirs(EXPORT_DIR, exist_ok=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(obj.type in {"MESH", "CURVE"} and obj.name != "Ground")

    path = os.path.join(EXPORT_DIR, "sawmill.fbx")
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


def main():
    clear_scene()
    build_materials()
    build_machine()
    setup_lighting()
    cam = setup_camera()
    setup_render()
    report_stats()
    render_views(cam)
    orient_for_roblox()
    join_by_material()
    export_fbx()


if __name__ == "__main__":
    main()

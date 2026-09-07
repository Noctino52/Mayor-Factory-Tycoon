"""
BeamCutter - a CNC beam saw, for Mayor's Factory Tycoon.

Run headless:
    blender --background --python modeling/beamcutter.py

Outputs:
    modeling/renders/beamcutter_<view>.png   preview renders to judge the shape
    modeling/export/beamcutter.fbx           import this into Roblox Studio

Conventions:
    1 Blender unit = 1 Roblox stud, fits one 8-stud cell (+/-4.0 on X and Y).
    Modelled Z-up; the exporter converts to Roblox's Y-up.
    X is the flow direction: a plank rolls in at -X, a beam leaves at +X.

    Shape reference: an industrial panel saw. A low white cabinet with a
    working table, a roller infeed on one side and a flat outfeed on the
    other, a bridge riding rails over the cutting line, a control console out
    front and an extraction tower at the back.

Animation groups (kept out of the static merge so Luau can drive them):
    BeamCutterHead_*   the bridge, its pressure beam and the saw blade,
                       swept along the cut by MachineSystem
Everything else merges into BeamCutter_*.
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
BODY_TOP = 1.08     # top of the cabinet
TABLE_TOP = 1.16    # the surface a plank actually rests on
RAIL_Z = 1.46       # centre line of the rails the bridge rides

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
    """A real round tube through the given points - used for hoses and ducts."""
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
    MAT["white_body"] = material("WhiteBody", (0.90, 0.90, 0.88), 0.05, 0.38)
    MAT["light_grey"] = material("LightGrey", (0.66, 0.67, 0.68), 0.20, 0.42)
    MAT["dark_panel"] = material("DarkPanel", (0.045, 0.045, 0.05), 0.35, 0.44)
    MAT["steel"] = material("Steel", (0.52, 0.55, 0.58), 0.85, 0.28)
    MAT["blade"] = material("Blade", (0.74, 0.77, 0.80), 0.95, 0.18)
    MAT["rubber"] = material("Rubber", (0.035, 0.035, 0.04), 0.0, 0.72)
    MAT["red_accent"] = material("RedAccent", (0.62, 0.06, 0.06), 0.20, 0.40)
    MAT["screen"] = material("Screen", (0.06, 0.20, 0.34), 0.10, 0.20)


# ---------------------------------------------------------------------------
# The machine
# ---------------------------------------------------------------------------


def build_body():
    """The white cabinet and the table on top of it, split by the saw line."""
    box("BodyMain", (3.30, 3.00, BODY_TOP - 0.10), (0, 0, 0.10 + (BODY_TOP - 0.10) / 2), MAT["white_body"], bevel=0.03)
    box("BodyPlinth", (3.24, 2.94, 0.12), (0, 0, 0.06), MAT["dark_panel"], bevel=0.02)

    # Table surface, and the slot the blade runs up through along the cut
    box("TableTop", (3.30, 3.00, 0.08), (0, 0, TABLE_TOP - 0.04), MAT["light_grey"], bevel=0.015)
    box("TableSlot", (3.30, 0.26, 0.06), (0, 0, TABLE_TOP - 0.04), MAT["dark_panel"], bevel=0.01)

    # Front face: louvres, a maker's badge and the red line the brand uses
    box("BodyStripe", (3.32, 0.05, 0.08), (0, -1.50, 0.84), MAT["red_accent"], bevel=0.01)
    for index, x in enumerate((-0.95, 0.0, 0.95)):
        box(f"BodyVent{index}", (0.56, 0.05, 0.26), (x, -1.50, 0.46), MAT["dark_panel"], bevel=0.01)
    box("BodyBadge", (0.46, 0.05, 0.13), (-1.20, -1.50, 0.84), MAT["dark_panel"], bevel=0.01)


def build_infeed():
    """
    Roller table on the -X side, where a plank is fed in. Wide and low on
    three legs: it is the part of a panel saw you actually recognise.
    """
    box("InfeedFrame", (2.20, 2.60, 0.14), (-2.85, 0, 0.93), MAT["white_body"], bevel=0.02)
    for index, y in enumerate((-1.24, 1.24)):
        box(f"InfeedSide{index}", (2.20, 0.12, 0.30), (-2.85, y, 1.06), MAT["white_body"], bevel=0.02)

    for index in range(5):
        x = -3.70 + index * 0.44
        cylinder(
            f"InfeedRoller{index}",
            0.11,
            2.34,
            (x, 0, TABLE_TOP - 0.08),
            MAT["dark_panel"],
            rotation=(math.radians(90), 0, 0),
            verts=14,
        )

    for index, x in enumerate((-3.60, -2.85, -2.10)):
        box(f"InfeedLeg{index}", (0.34, 1.70, 0.86), (x, 0, 0.43), MAT["white_body"], bevel=0.02)
        box(f"InfeedFoot{index}", (0.44, 1.80, 0.06), (x, 0, 0.03), MAT["dark_panel"], bevel=0.015)


def build_outfeed():
    """Flat table on the +X side, running off the cabinet, where the beam lands."""
    box("OutfeedTable", (2.30, 2.20, 0.10), (2.70, 0, TABLE_TOP - 0.05), MAT["white_body"], bevel=0.02)
    box("OutfeedApron", (2.30, 2.20, 0.16), (2.70, 0, TABLE_TOP - 0.18), MAT["light_grey"], bevel=0.02)
    for index, y in enumerate((-1.02, 1.02)):
        box(f"OutfeedLip{index}", (2.30, 0.10, 0.16), (2.70, y, TABLE_TOP + 0.04), MAT["light_grey"], bevel=0.02)
    for index, x in enumerate((2.10, 3.45)):
        box(f"OutfeedLeg{index}", (0.32, 1.70, 0.90), (x, 0, 0.45), MAT["white_body"], bevel=0.02)
        box(f"OutfeedFoot{index}", (0.42, 1.80, 0.06), (x, 0, 0.03), MAT["dark_panel"], bevel=0.015)


def build_gantry():
    """Rails and posts the cutting bridge rides on, and its cable chain."""
    for index, (x, y) in enumerate(((-1.45, -1.62), (1.45, -1.62), (-1.45, 1.62), (1.45, 1.62))):
        box(
            f"RailPost{index}",
            (0.22, 0.22, RAIL_Z - BODY_TOP + 0.10),
            (x, y, (RAIL_Z + BODY_TOP) / 2),
            MAT["white_body"],
            bevel=0.02,
        )

    for index, y in enumerate((-1.62, 1.62)):
        box(f"Rail{index}", (3.70, 0.13, 0.13), (0, y, RAIL_Z), MAT["steel"], bevel=0.02)

    # Cable chain looping along the back rail
    for index in range(11):
        x = -1.40 + index * 0.28
        box(f"CableChain{index}", (0.18, 0.11, 0.11), (x, 1.62, RAIL_Z + 0.17), MAT["dark_panel"], bevel=0.015)


def build_head():
    """
    The travelling bridge: a beam across the machine carrying the pressure
    bar that holds the piece down and the saw that rips it. Named Head* so it
    stays out of the static merge and the game can slide it along the cut.
    """
    box("HeadBridge", (0.46, 3.44, 0.22), (-0.36, 0, RAIL_Z + 0.25), MAT["white_body"], bevel=0.02)
    box("HeadBridgeCap", (0.50, 3.48, 0.05), (-0.36, 0, RAIL_Z + 0.38), MAT["light_grey"], bevel=0.015)

    for index, y in enumerate((-1.62, 1.62)):
        box(f"HeadEndCar{index}", (0.80, 0.30, 0.28), (-0.24, y, RAIL_Z), MAT["white_body"], bevel=0.02)

    # Pressure bar, hung under the bridge just ahead of the cut. Offset from
    # the blade rather than sat on top of it: that is where a beam saw clamps,
    # and it leaves the blade in plain sight.
    for index, y in enumerate((-0.95, 0.95)):
        box(f"HeadRiser{index}", (0.13, 0.13, 0.30), (-0.36, y, RAIL_Z), MAT["steel"], bevel=0.015)
    box("HeadPressureBeam", (0.30, 3.00, 0.18), (-0.36, 0, TABLE_TOP + 0.25), MAT["light_grey"], bevel=0.02)
    box("HeadPressurePad", (0.34, 3.04, 0.06), (-0.36, 0, TABLE_TOP + 0.13), MAT["rubber"], bevel=0.012)

    # The blade, standing well proud of the table so the cut is readable
    cylinder(
        "HeadBlade",
        0.36,
        0.05,
        (0.16, 0, TABLE_TOP - 0.20),
        MAT["blade"],
        rotation=(math.radians(90), 0, 0),
        verts=28,
    )
    box("HeadBladeGuard", (0.44, 0.20, 0.34), (0.16, 0.30, TABLE_TOP + 0.10), MAT["dark_panel"], bevel=0.02)
    box("HeadBladeHood", (0.66, 0.24, 0.09), (0.16, 0.30, TABLE_TOP + 0.30), MAT["red_accent"], bevel=0.015)


def build_console():
    """Operator station out in front, on the infeed side."""
    box("ConsolePost", (0.28, 0.28, 1.12), (-1.95, -2.05, 0.56), MAT["white_body"], bevel=0.02)
    box("ConsoleShelf", (0.84, 0.44, 0.06), (-1.95, -2.19, 1.14), MAT["light_grey"], bevel=0.015)
    box("ConsoleKeys", (0.62, 0.26, 0.04), (-1.95, -2.23, 1.19), MAT["dark_panel"], bevel=0.01)

    box(
        "ConsoleBody",
        (0.88, 0.16, 0.58),
        (-1.95, -2.11, 1.52),
        MAT["white_body"],
        rotation=(math.radians(18), 0, 0),
        bevel=0.02,
    )
    box(
        "ConsoleScreen",
        (0.74, 0.05, 0.44),
        (-1.95, -2.19, 1.53),
        MAT["screen"],
        rotation=(math.radians(18), 0, 0),
        bevel=0.01,
    )


def build_extraction():
    """Extraction tower at the back, ducted into the cabinet."""
    box("HousingBody", (1.30, 1.40, 2.00), (2.55, 1.60, 1.00), MAT["white_body"], bevel=0.03)
    box("HousingCap", (1.36, 1.46, 0.08), (2.55, 1.60, 2.02), MAT["light_grey"], bevel=0.02)
    box("HousingPanel", (1.06, 0.05, 0.62), (2.55, 0.89, 1.44), MAT["dark_panel"], bevel=0.02)
    box("HousingLogo", (0.34, 0.05, 0.34), (2.55, 0.89, 0.66), MAT["red_accent"], bevel=0.01)
    box("HousingFoot", (1.24, 1.34, 0.10), (2.55, 1.60, 0.05), MAT["dark_panel"], bevel=0.02)

    tube(
        "HousingDuct",
        [(1.05, 1.02, 1.22), (1.72, 1.26, 1.44), (2.05, 1.54, 1.40)],
        0.14,
        MAT["steel"],
    )


def build_machine():
    build_body()
    build_infeed()
    build_outfeed()
    build_gantry()
    build_head()
    build_console()
    build_extraction()


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
    "hero": (9.2, -9.8, 5.0),
    "side": (0.2, -11.5, 2.4),
    "top": (5.6, -6.2, 10.0),
}


def render_views(cam):
    os.makedirs(RENDER_DIR, exist_ok=True)
    for name, location in VIEWS.items():
        cam.location = location
        bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"beamcutter_{name}.png")
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

    print("\n=== BeamCutter stats ===")
    print(f"objects  : {objects}")
    print(f"triangles: {triangles} total, worst single part {worst_object[0]} at {worst_object[1]}")
    print(f"bounds X : {min_corner[0]:.2f} .. {max_corner[0]:.2f}  (cell limit +/-{CELL_HALF})")
    print(f"bounds Y : {min_corner[1]:.2f} .. {max_corner[1]:.2f}  (cell limit +/-{CELL_HALF})")
    print(f"height   : {max_corner[2]:.2f}")
    print(f"cut line : {(min_corner[1] + max_corner[1]) / 2:+.2f} off the model centre in Y")

    if max(abs(min_corner[0]), abs(max_corner[0]), abs(min_corner[1]), abs(max_corner[1])) > CELL_HALF:
        print("WARNING: the model crosses the grid cell boundary")
    if worst_object[1] > 10000:
        print("WARNING: a single part is over the MeshPart triangle budget")


def _group_prefix(obj):
    return "BeamCutterHead" if obj.name.startswith("Head") else "BeamCutter"


def orient_for_roblox():
    """
    Roblox's FBX import mirrors X relative to how the model is built here.
    A rigid 180-degree turn about Z cancels it, unlike mirroring the geometry
    which would invert the normals. Z ends up negated, which is harmless as
    the machine is symmetric across the flow line.
    """
    import mathutils

    turn = mathutils.Matrix.Rotation(math.pi, 4, "Z")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "CURVE"} and obj.name != "Ground":
            obj.matrix_world = turn @ obj.matrix_world


def join_by_material():
    """
    Collapse the build into one mesh per material, keeping the cutting bridge
    as its own set of parts so it stays animatable. Every object would
    otherwise import as its own MeshPart, and a hundred parts per machine adds
    up fast across six players' plots.

    Resulting names are BeamCutter_<Material> and BeamCutterHead_<Material>,
    which the game reads back to re-apply colours after import.
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

    path = os.path.join(EXPORT_DIR, "beamcutter.fbx")
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


main()

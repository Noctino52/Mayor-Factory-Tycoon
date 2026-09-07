"""
CrateAssembler - a gantry nailing press, for Mayor's Factory Tycoon.

Run headless:
    blender --background --python modeling/crateassembler.py

Outputs:
    modeling/renders/crateassembler_<view>.png   previews to judge the shape
    modeling/export/crateassembler.fbx           import this into Studio

Conventions:
    1 Blender unit = 1 Roblox stud, fits one 8-stud cell (+/-4.0 on X and Y).
    Modelled Z-up; the exporter converts to Roblox's Y-up.
    X is the flow direction: beams arrive at -X, a crate leaves at +X.

    Shape reference: the pallet and crate nailing presses used in timber
    yards. A heavy steel table, a chain conveyor feeding boards into a jig
    between four guide posts, and a platen of nail guns that drops onto the
    stack and lifts off again.

Animation groups (kept out of the static merge so Luau can drive them):
    CrateAssemblerHead_*   the platen, its rams and the nail guns, driven
                           down onto the work and back up by MachineSystem
Everything else merges into CrateAssembler_*.
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
TABLE_TOP = 1.00    # the jig surface the boards are laid on
POST_TOP = 3.10     # top of the four guide posts
PLATEN_Z = 2.75     # the platen at rest, before it drops onto the work

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
    MAT["steel_blue"] = material("SteelBlue", (0.10, 0.24, 0.38), 0.35, 0.40)
    MAT["graphite"] = material("Graphite", (0.13, 0.14, 0.15), 0.45, 0.44)
    MAT["hazard_yellow"] = material("HazardYellow", (0.85, 0.66, 0.06), 0.25, 0.42)
    MAT["steel"] = material("Steel", (0.52, 0.55, 0.58), 0.85, 0.28)
    MAT["dark_metal"] = material("DarkMetal", (0.055, 0.055, 0.065), 0.55, 0.42)
    MAT["rubber"] = material("Rubber", (0.035, 0.035, 0.04), 0.0, 0.72)
    MAT["screen"] = material("Screen", (0.06, 0.20, 0.34), 0.10, 0.20)


# ---------------------------------------------------------------------------
# The machine
# ---------------------------------------------------------------------------


def build_frame():
    """Heavy welded table the whole press stands on."""
    for index, y in enumerate((-1.40, 1.40)):
        box(f"FrameRail{index}", (6.40, 0.22, 0.34), (0, y, TABLE_TOP - 0.17), MAT["steel_blue"], bevel=0.025)
    for index, x in enumerate((-2.90, -1.60, -0.30, 1.00, 2.30, 2.90)):
        box(f"FrameCross{index}", (0.18, 2.80, 0.20), (x, 0, TABLE_TOP - 0.28), MAT["graphite"], bevel=0.02)

    for index, (x, y) in enumerate(((-2.85, -1.40), (2.85, -1.40), (-2.85, 1.40), (2.85, 1.40))):
        box(f"FrameLeg{index}", (0.30, 0.30, TABLE_TOP - 0.34), (x, y, (TABLE_TOP - 0.34) / 2), MAT["steel_blue"], bevel=0.02)
        box(f"FramePad{index}", (0.42, 0.42, 0.06), (x, y, 0.03), MAT["dark_metal"], bevel=0.015)

    # Hazard stripe along the front rail, the way a press is always marked
    box("FrameStripe", (6.42, 0.05, 0.12), (0, -1.52, TABLE_TOP - 0.12), MAT["hazard_yellow"], bevel=0.01)


def build_jig():
    """The bed in the middle: slats to nail against, and squaring fences."""
    for index, y in enumerate((-0.90, -0.30, 0.30, 0.90)):
        box(f"JigSlat{index}", (2.60, 0.34, 0.10), (0.10, y, TABLE_TOP - 0.05), MAT["graphite"], bevel=0.02)

    # Fixed fence at the far end, a moving stop at the near end
    box("JigFence", (0.16, 2.30, 0.34), (1.52, 0, TABLE_TOP + 0.12), MAT["hazard_yellow"], bevel=0.025)
    box("JigStop", (0.16, 2.30, 0.26), (-1.30, 0, TABLE_TOP + 0.08), MAT["steel"], bevel=0.025)
    for index, y in enumerate((-1.16, 1.16)):
        box(f"JigSideGuide{index}", (2.90, 0.14, 0.22), (0.10, y, TABLE_TOP + 0.06), MAT["steel"], bevel=0.02)


def build_infeed():
    """Chain conveyor bringing beams in, with lugs to push them along."""
    box("InfeedBed", (2.10, 2.40, 0.14), (-2.45, 0, TABLE_TOP - 0.07), MAT["graphite"], bevel=0.02)
    for index, y in enumerate((-0.62, 0.62)):
        box(f"InfeedChain{index}", (2.10, 0.16, 0.08), (-2.45, y, TABLE_TOP + 0.01), MAT["dark_metal"], bevel=0.015)
        for lug in range(4):
            x = -3.20 + lug * 0.52
            box(f"InfeedLug{index}{lug}", (0.10, 0.16, 0.16), (x, y, TABLE_TOP + 0.09), MAT["hazard_yellow"], bevel=0.015)

    for index, x in enumerate((-3.30, -1.70)):
        cylinder(
            f"InfeedShaft{index}",
            0.10,
            1.70,
            (x, 0, TABLE_TOP - 0.06),
            MAT["steel"],
            rotation=(math.radians(90), 0, 0),
            verts=12,
        )


def build_outfeed():
    """Roller table the finished crate is pushed out onto."""
    box("OutfeedFrame", (1.90, 2.40, 0.14), (2.55, 0, TABLE_TOP - 0.07), MAT["steel_blue"], bevel=0.02)
    for index in range(4):
        x = 1.85 + index * 0.46
        cylinder(
            f"OutfeedRoller{index}",
            0.10,
            2.20,
            (x, 0, TABLE_TOP + 0.04),
            MAT["dark_metal"],
            rotation=(math.radians(90), 0, 0),
            verts=12,
        )
    for index, y in enumerate((-1.22, 1.22)):
        box(f"OutfeedLip{index}", (1.90, 0.10, 0.20), (2.55, y, TABLE_TOP + 0.08), MAT["hazard_yellow"], bevel=0.02)


def build_gantry():
    """Four guide posts and the crown the rams hang from."""
    for index, (x, y) in enumerate(((-1.15, -1.25), (1.35, -1.25), (-1.15, 1.25), (1.35, 1.25))):
        box(
            f"GuidePost{index}",
            (0.26, 0.26, POST_TOP - TABLE_TOP),
            (x, y, (POST_TOP + TABLE_TOP) / 2),
            MAT["steel_blue"],
            bevel=0.025,
        )
        box(f"PostShoe{index}", (0.42, 0.42, 0.10), (x, y, TABLE_TOP + 0.05), MAT["graphite"], bevel=0.02)

    for index, y in enumerate((-1.25, 1.25)):
        box(f"CrownBeam{index}", (2.90, 0.28, 0.26), (0.10, y, POST_TOP + 0.13), MAT["steel_blue"], bevel=0.025)
    box("CrownPlate", (2.90, 2.78, 0.16), (0.10, 0, POST_TOP + 0.34), MAT["graphite"], bevel=0.025)

    # Hydraulic pack sitting on the crown, and the line running down a post
    box("PowerPack", (1.10, 0.90, 0.46), (-0.70, 0, POST_TOP + 0.65), MAT["steel_blue"], bevel=0.025)
    cylinder("PowerTank", 0.22, 1.00, (0.90, 0, POST_TOP + 0.62), MAT["steel"], rotation=(0, math.radians(90), 0), verts=16)
    # Air line from the pack to the near post: two straight runs rather than a
    # curve, which is all that reads at this size and costs a tenth as much
    box("AirLineTop", (0.90, 0.09, 0.09), (-1.10, -0.62, POST_TOP + 0.46), MAT["rubber"], bevel=0.02)
    box("AirLineDrop", (0.09, 0.09, 1.60), (-1.15, -1.05, POST_TOP - 0.55), MAT["rubber"], bevel=0.02)
    box("AirLineElbow", (0.11, 0.90, 0.11), (-1.15, -0.84, POST_TOP + 0.30), MAT["rubber"], bevel=0.02)


def build_head():
    """
    The platen: the beam of nail guns that drops onto the stack. Named Head*
    so it stays out of the static merge and the game can drive the stroke.
    """
    box("HeadPlaten", (2.30, 2.40, 0.30), (0.10, 0, PLATEN_Z), MAT["steel_blue"], bevel=0.025)
    box("HeadPlatenFace", (2.34, 2.44, 0.08), (0.10, 0, PLATEN_Z - 0.19), MAT["graphite"], bevel=0.02)
    box("HeadWarning", (2.34, 0.05, 0.10), (0.10, -1.23, PLATEN_Z + 0.10), MAT["hazard_yellow"], bevel=0.01)

    # Nail guns hanging under it, in two rows over the joints
    for row, x in enumerate((-0.55, 0.75)):
        for index, y in enumerate((-0.85, -0.28, 0.28, 0.85)):
            box(f"HeadGun{row}{index}", (0.22, 0.22, 0.26), (x, y, PLATEN_Z - 0.28), MAT["graphite"], bevel=0.02)
            cylinder(f"HeadNose{row}{index}", 0.05, 0.06, (x, y, PLATEN_Z - 0.43), MAT["steel"], verts=10)

    # Rams from the crown, and the shoes that ride the guide posts
    for index, x in enumerate((-0.70, 0.90)):
        cylinder(f"HeadRam{index}", 0.13, 0.90, (x, 0, PLATEN_Z + 0.60), MAT["steel"], verts=16)
    for index, (x, y) in enumerate(((-1.15, -1.25), (1.35, -1.25), (-1.15, 1.25), (1.35, 1.25))):
        box(f"HeadShoe{index}", (0.40, 0.40, 0.34), (x, y, PLATEN_Z), MAT["graphite"], bevel=0.025)


def build_console():
    """Operator panel on the front corner, clear of the press."""
    box("ConsolePost", (0.26, 0.26, 1.20), (-2.30, -1.85, 0.60), MAT["steel_blue"], bevel=0.02)
    box(
        "ConsoleBody",
        (0.80, 0.20, 0.60),
        (-2.30, -1.92, 1.55),
        MAT["steel_blue"],
        rotation=(math.radians(18), 0, 0),
        bevel=0.02,
    )
    box(
        "ConsoleScreen",
        (0.64, 0.05, 0.44),
        (-2.30, -2.00, 1.56),
        MAT["screen"],
        rotation=(math.radians(18), 0, 0),
        bevel=0.01,
    )
    box("ConsoleStop", (0.16, 0.06, 0.16), (-1.95, -1.86, 1.20), MAT["hazard_yellow"], bevel=0.02)

    box("PanelCabinet", (0.90, 0.52, 1.50), (-2.30, 1.86, 0.75), MAT["steel_blue"], bevel=0.025)
    box("PanelDoor", (0.72, 0.05, 1.10), (-2.30, 1.59, 0.82), MAT["graphite"], bevel=0.02)
    box("PanelLamp", (0.12, 0.06, 0.12), (-2.68, 1.59, 1.62), MAT["hazard_yellow"], bevel=0.02)
    box("PanelRoof", (0.96, 0.58, 0.06), (-2.30, 1.86, 1.53), MAT["graphite"], bevel=0.02)


def build_machine():
    build_frame()
    build_jig()
    build_infeed()
    build_outfeed()
    build_gantry()
    build_head()
    build_console()


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
    target.location = (0, 0, 1.5)
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
    "hero": (9.4, -9.8, 6.0),
    "side": (0.2, -11.5, 3.0),
    "top": (5.6, -6.4, 10.6),
}


def render_views(cam):
    os.makedirs(RENDER_DIR, exist_ok=True)
    for name, location in VIEWS.items():
        cam.location = location
        bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"crateassembler_{name}.png")
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

    print("\n=== CrateAssembler stats ===")
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
    return "CrateAssemblerHead" if obj.name.startswith("Head") else "CrateAssembler"


def orient_for_roblox():
    """
    Roblox's FBX import mirrors X relative to how the model is built here.
    A rigid 180-degree turn about Z cancels it, unlike mirroring the geometry
    which would invert the normals. Z ends up negated, which is harmless as
    the press is symmetric across the flow line.
    """
    import mathutils

    turn = mathutils.Matrix.Rotation(math.pi, 4, "Z")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "CURVE"} and obj.name != "Ground":
            obj.matrix_world = turn @ obj.matrix_world


def join_by_material():
    """
    Collapse the build into one mesh per material, keeping the platen as its
    own set of parts so it stays animatable. Every object would
    otherwise import as its own MeshPart, and a hundred parts per machine adds
    up fast across six players' plots.

    Resulting names are CrateAssembler_<Material> and
    CrateAssemblerHead_<Material>, read back to re-apply colours after import.
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

    path = os.path.join(EXPORT_DIR, "crateassembler.fbx")
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

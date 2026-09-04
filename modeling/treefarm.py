"""
TreeFarm - a small plantation worked by an axeman, for Mayor's Factory Tycoon.

Run headless:
    blender --background --python modeling/treefarm.py

Outputs:
    modeling/renders/treefarm_<view>.png
    modeling/export/treefarm.fbx

Conventions:
    1 Blender unit = 1 Roblox stud, fits one 8-stud cell (+/-4.0 on X and Y).
    Modelled Z-up; the exporter converts to Roblox's Y-up.
    The machine has no input; logs leave at +X, so the drop-off is that side.

Animation groups (kept out of the static merge so Luau can drive them):
    TreeFarmTree1_* .. TreeFarmTree6_*   the six planted trees, felled and
                                         regrown in turn by the worker
Everything else merges into TreeFarm_* and never moves.

The lumberjack, his axe and the log are NOT modelled here: they are built at
runtime from native Roblox parts so they match the game's own art style.
"""

import math
import os

import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RENDER_DIR = os.path.join(SCRIPT_DIR, "renders")
EXPORT_DIR = os.path.join(SCRIPT_DIR, "export")

CELL_HALF = 4.0

GROUND_TOP = 0.20
ROW_X = (-2.15, 0.00, 2.15)   # three planting stations per side
ROW_Y = 1.95                 # distance of each row from the central road
DROP_AT = (3.05, 0.0)

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
        mod.angle_limit = math.radians(35)
        mod.harden_normals = True

    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def box(name, size, location, mat, rotation=(0, 0, 0), bevel=0.02, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    return _finish(obj, mat, bevel, segments)


def cylinder(name, radius, depth, location, mat, rotation=(0, 0, 0), verts=16, bevel=0.01):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, bevel, 1)


def cone(name, radius, depth, location, mat, rotation=(0, 0, 0), verts=14, bevel=0.0):
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=radius, radius2=0.0, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, bevel, 1)


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

MAT = {}


def build_materials():
    # Ground deliberately matches the plot floor (Roblox rgb 34,139,34)
    MAT["grass"] = material("Grass", (0.045, 0.26, 0.045), 0.0, 0.80)
    MAT["dirt"] = material("Dirt", (0.20, 0.13, 0.075), 0.0, 0.85)
    MAT["bark"] = material("Bark", (0.115, 0.070, 0.038), 0.0, 0.80)
    MAT["foliage"] = material("Foliage", (0.035, 0.175, 0.045), 0.0, 0.72)


# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------


def build_ground():
    """Grass pad matching the plot floor, with one straight haul road."""
    box("GroundPad", (7.00, 7.00, GROUND_TOP), (0, 0, GROUND_TOP / 2), MAT["grass"], bevel=0.04)

    # The road runs straight through, from the back of the plot to the output
    box("Road", (6.90, 1.30, 0.05), (0, 0, GROUND_TOP + 0.012), MAT["dirt"], bevel=0.02)
    for index, y in enumerate((-0.68, 0.68)):
        box(f"RoadKerb{index}", (6.90, 0.10, 0.10), (0, y, GROUND_TOP + 0.04), MAT["bark"], bevel=0.02)

    # Log pile at the drop-off end
    for index, (offset, lift) in enumerate(((-0.16, 0.0), (0.16, 0.0), (0.0, 0.26))):
        cylinder(
            f"PileLog{index}",
            0.15,
            1.10,
            (DROP_AT[0], DROP_AT[1] + offset, GROUND_TOP + 0.16 + lift),
            MAT["bark"],
            rotation=(0, math.radians(90), 0),
            verts=12,
        )
    for index, x in enumerate((-0.62, 0.62)):
        box(
            f"PileStake{index}",
            (0.10, 0.10, 0.62),
            (DROP_AT[0] + x, DROP_AT[1], GROUND_TOP + 0.31),
            MAT["bark"],
            bevel=0.02,
        )


def spawn_tree(prefix, x, y, scale=1.0):
    """A stylised conifer standing in its own tilled planting bed."""
    # Planting bed and stump stay behind when the tree is felled, so they are
    # deliberately named outside the tree's animation group
    box(f"BedOf{prefix}", (1.15, 1.15, 0.10), (x, y, GROUND_TOP + 0.05), MAT["dirt"], bevel=0.03)
    box(f"BedRimOf{prefix}", (1.28, 1.28, 0.06), (x, y, GROUND_TOP + 0.02), MAT["bark"], bevel=0.02)
    cylinder(f"StumpOf{prefix}", 0.20, 0.14, (x, y, GROUND_TOP + 0.15), MAT["bark"], verts=10)

    trunk_h = 1.15 * scale
    cylinder(
        f"{prefix}Trunk",
        0.17 * scale,
        trunk_h,
        (x, y, GROUND_TOP + 0.10 + trunk_h / 2),
        MAT["bark"],
        verts=12,
    )

    base_z = GROUND_TOP + 0.10 + trunk_h
    for index, (radius, depth, offset) in enumerate(((0.92, 0.95, 0.00), (0.72, 0.85, 0.62), (0.48, 0.75, 1.15))):
        cone(
            f"{prefix}Tier{index}",
            radius * scale,
            depth * scale,
            (x, y, base_z + (offset + depth / 2) * scale - 0.10 * scale),
            MAT["foliage"],
            verts=14,
        )


def build_trees():
    """Three trees each side of the road, evenly spaced like a real plantation."""
    for index, x in enumerate(ROW_X):
        spawn_tree(f"Tree{index + 1}", x, -ROW_Y, scale=0.80)
        spawn_tree(f"Tree{index + 4}", x, ROW_Y, scale=0.80)


def build_machine():
    build_ground()
    build_trees()


# ---------------------------------------------------------------------------
# Grouping for export
# ---------------------------------------------------------------------------

GROUPS = tuple(
    (f"TreeFarmTree{index}", (f"Tree{index}",)) for index in range(1, 7)
)


def _group_prefix(obj):
    for prefix, starts in GROUPS:
        for start in starts:
            if obj.name.startswith(start):
                return prefix
    return "TreeFarm"


# ---------------------------------------------------------------------------
# Render + export
# ---------------------------------------------------------------------------


def setup_lighting():
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.60, 0.68, 0.78, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    bpy.context.scene.world = world

    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 950
    key.size = 7
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (5.5, -5.5, 7.0)
    key_obj.rotation_euler = (math.radians(46), 0, math.radians(44))
    bpy.context.scene.collection.objects.link(key_obj)

    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 300
    fill.size = 9
    fill_obj = bpy.data.objects.new("Fill", fill)
    fill_obj.location = (-6.0, -3.5, 4.5)
    fill_obj.rotation_euler = (math.radians(62), 0, math.radians(-58))
    bpy.context.scene.collection.objects.link(fill_obj)

    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.01))
    ground = bpy.context.active_object
    ground.name = "Ground"
    ground.data.materials.append(material("Backdrop", (0.10, 0.30, 0.09), 0.0, 0.9))


def setup_camera():
    target = bpy.data.objects.new("CamTarget", None)
    target.location = (0, 0, 1.0)
    bpy.context.scene.collection.objects.link(target)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 48
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
    "hero": (6.8, -7.4, 4.6),
    "worker": (2.6, -4.6, 2.2),
}


def render_views(cam):
    os.makedirs(RENDER_DIR, exist_ok=True)
    for name, location in VIEWS.items():
        cam.location = location
        bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"treefarm_{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[render] {name}")


def report_stats():
    from mathutils import Vector

    depsgraph = bpy.context.evaluated_depsgraph_get()
    triangles = 0
    objects = 0
    min_corner = [1e9, 1e9, 1e9]
    max_corner = [-1e9, -1e9, -1e9]

    for obj in bpy.context.scene.objects:
        if obj.type not in {"MESH", "CURVE"} or obj.name == "Ground":
            continue

        objects += 1
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        triangles += len(mesh.loop_triangles)
        evaluated.to_mesh_clear()

        for corner in evaluated.bound_box:
            world_corner = evaluated.matrix_world @ Vector(corner)
            for axis in range(3):
                min_corner[axis] = min(min_corner[axis], world_corner[axis])
                max_corner[axis] = max(max_corner[axis], world_corner[axis])

    print("\n=== TreeFarm stats ===")
    print(f"objects  : {objects}")
    print(f"triangles: {triangles}")
    print(f"bounds X : {min_corner[0]:.2f} .. {max_corner[0]:.2f}  (cell limit +/-{CELL_HALF})")
    print(f"bounds Y : {min_corner[1]:.2f} .. {max_corner[1]:.2f}  (cell limit +/-{CELL_HALF})")
    print(f"height   : {max_corner[2]:.2f}")

    if max(abs(min_corner[0]), abs(max_corner[0]), abs(min_corner[1]), abs(max_corner[1])) > CELL_HALF:
        print("WARNING: the model crosses the grid cell boundary")



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

    path = os.path.join(EXPORT_DIR, "treefarm.fbx")
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

"""
Accessories for the three traders - for Mayor's Factory Tycoon.

Run headless:
    blender --background --python modeling/accessories.py

Outputs, one set per accessory:
    modeling/renders/acc_<name>.png     preview, shown on a stand-in head
    modeling/export/acc_<name>.fbx      upload this as a mesh

Conventions:
    1 Blender unit = 1 Roblox stud, at full R6 size. The game scales them
    down with the figure.
    The origin is the centre of the R6 head, which is where the game hangs
    them from: an accessory is modelled where it sits, so placing it needs
    no offsets guessed at the other end.
    Modelled Z-up; the exporter converts to Roblox's Y-up.

    Every one of them is symmetric across X. That is deliberate: Roblox's
    importer mirrors X, and a symmetric mesh does not care.

The clothes are textures (see clothing.py); these are the things a texture
cannot do - a brim, a chin, a plait.
"""

import math
import os

import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RENDER_DIR = os.path.join(SCRIPT_DIR, "renders")
EXPORT_DIR = os.path.join(SCRIPT_DIR, "export")

# The R6 head, as the mesh sees it: 2 x 1 x 1 studs with the head mesh's
# 1.25 scale on it, centred on the origin.
HEAD_W = 2.5
HEAD_H = 1.25
HEAD_D = 1.25
HEAD_TOP = HEAD_H / 2

PREVIEW = "PreviewHead"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            block.remove(item)


def material(name, color, roughness=0.55):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def _finish(obj, mat, bevel, segments=2):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)

    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(40)
        mod.harden_normals = True

    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def box(name, size, location, mat, rotation=(0, 0, 0), bevel=0.06, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    return _finish(obj, mat, bevel, segments)


def ball(name, size, location, mat, segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2, radius=0.5, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    return _finish(obj, mat, 0)


def cylinder(name, radius, depth, location, mat, rotation=(0, 0, 0), verts=20):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, 0.03, 1)


def cone(name, lower, upper, depth, location, mat, rotation=(0, 0, 0), verts=18):
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=lower, radius2=upper, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, 0.02, 1)


def preview_head():
    """A stand-in head, so a shape can be judged where it will actually sit."""
    head = box(PREVIEW, (HEAD_W, HEAD_D, HEAD_H), (0, 0, 0), material("Skin", (0.92, 0.74, 0.58)), bevel=0.18, segments=4)
    return head


# ---------------------------------------------------------------------------
# The accessories
# ---------------------------------------------------------------------------

MAT = {}


def build_materials():
    MAT["hi_vis"] = material("HiVis", (0.86, 0.56, 0.05), 0.42)
    MAT["hi_vis_deep"] = material("HiVisDeep", (0.62, 0.38, 0.02), 0.42)
    MAT["hair_dark"] = material("HairDark", (0.14, 0.08, 0.045), 0.70)
    MAT["hair_black"] = material("HairBlack", (0.045, 0.04, 0.045), 0.72)
    MAT["hair_fair"] = material("HairFair", (0.60, 0.44, 0.16), 0.70)
    MAT["cloth_dark"] = material("ClothDark", (0.16, 0.17, 0.18), 0.74)
    MAT["leather"] = material("Leather", (0.14, 0.09, 0.05), 0.62)


def build_hardhat():
    """
    A builder's hard hat. The shell sits above the brow and the brim runs
    round under it, which is what keeps it off the face: a dome pushed down
    over the eyes reads as a helmet, not a hat.
    """
    ball("Shell", (2.36, 2.20, 1.24), (0, 0, HEAD_TOP + 0.10), MAT["hi_vis"], segments=28)
    cylinder("Brim", 1.42, 0.10, (0, -0.06, HEAD_TOP - 0.02), MAT["hi_vis"], verts=30)
    box("Peak", (1.40, 0.86, 0.12), (0, -1.30, HEAD_TOP), MAT["hi_vis"],
        rotation=(math.radians(-12), 0, 0), bevel=0.05)
    box("Ridge", (0.34, 1.30, 0.18), (0, 0, HEAD_TOP + 0.62), MAT["hi_vis_deep"], bevel=0.08, segments=3)
    for side in (-1, 1):
        box(f"Vent{side}", (0.14, 0.90, 0.12), (side * 0.66, 0, HEAD_TOP + 0.54), MAT["hi_vis_deep"], bevel=0.05)


def build_hair_long():
    """
    Shoulder-length hair: a crown over the skull, a mass down the back, and
    a plait. Rounded throughout - hair has no flat faces, and a slab of it
    beside the head reads as a plank.
    """
    ball("Crown", (2.70, 2.10, 1.44), (0, 0.24, HEAD_TOP - 0.16), MAT["hair_dark"], segments=28)
    ball("Back", (2.34, 1.16, 2.10), (0, 0.86, -0.44), MAT["hair_dark"], segments=24)
    for side in (-1, 1):
        ball(f"Side{side}", (0.62, 1.50, 2.00), (side * 1.12, 0.14, -0.42), MAT["hair_dark"], segments=20)
    cone("Plait", 0.42, 0.14, 1.30, (0, 1.02, -1.55), MAT["hair_dark"],
         rotation=(math.radians(180), 0, 0), verts=16)
    cylinder("PlaitTie", 0.34, 0.16, (0, 1.00, -1.02), MAT["leather"], verts=14)


def _beard(colour, mass, point_depth, moustache):
    """
    The shape a beard actually is: a mass over the jaw and chin, sideburns
    joining it at the cheeks, and a tapered point below.

    It has to sit ON the lower head, not hang under it - the head runs from
    -0.63 to +0.63, and a mass centred much below that reads as a sack tied
    to the chin. The top edge stops short of the eyes.
    """
    ball("Mass", mass, (0, -0.38, -0.44), colour, segments=24)
    for side in (-1, 1):
        ball(f"Cheek{side}", (0.66, 1.16, 1.30), (side * 1.02, -0.14, -0.06), colour, segments=18)
    cone("Point", 0.50, 0.10, point_depth, (0, -0.44, -0.94 - point_depth / 2), colour,
         rotation=(math.radians(180), 0, 0), verts=16)
    if moustache:
        ball("Moustache", (1.20, 0.44, 0.32), (0, -0.66, -0.06), colour, segments=18)


def build_beard_full():
    """The mason's: black, square and close to the jaw."""
    _beard(MAT["hair_black"], (2.26, 1.46, 1.34), 0.62, True)


def build_beard_smith():
    """The smith's: fair, and longer than the mason's."""
    _beard(MAT["hair_fair"], (2.34, 1.54, 1.46), 0.88, True)


def build_cap_soft():
    """A soft cap with a band round it, the sort a smith works in."""
    ball("Shell", (2.32, 2.22, 1.16), (0, 0.06, HEAD_TOP), MAT["cloth_dark"], segments=26)
    cylinder("Band", 1.19, 0.20, (0, 0.06, HEAD_TOP - 0.06), MAT["leather"], verts=28)
    ball("Stud", (0.30, 0.30, 0.22), (0, 0.06, HEAD_TOP + 0.58), MAT["leather"], segments=12)


ACCESSORIES = (
    ("hardhat", build_hardhat),
    ("hair_long", build_hair_long),
    ("beard_full", build_beard_full),
    ("beard_smith", build_beard_smith),
    ("cap_soft", build_cap_soft),
)


# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------


def setup_lighting():
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.70, 0.74, 0.80, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.3
    bpy.context.scene.world = world

    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 260
    key.size = 4
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (2.6, -3.4, 3.4)
    key_obj.rotation_euler = (math.radians(42), 0, math.radians(38))
    bpy.context.scene.collection.objects.link(key_obj)

    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 110
    fill.size = 5
    fill_obj = bpy.data.objects.new("Fill", fill)
    fill_obj.location = (-3.2, -2.6, 1.6)
    fill_obj.rotation_euler = (math.radians(72), 0, math.radians(-54))
    bpy.context.scene.collection.objects.link(fill_obj)


def setup_camera():
    target = bpy.data.objects.new("CamTarget", None)
    target.location = (0, 0, 0)
    bpy.context.scene.collection.objects.link(target)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 70
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
    scene.cycles.samples = 36
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 560
    scene.render.resolution_y = 460
    scene.render.image_settings.file_format = "PNG"


def render(cam, name):
    os.makedirs(RENDER_DIR, exist_ok=True)
    cam.location = (4.6, -6.6, 2.6)
    bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"acc_{name}.png")
    bpy.ops.render.render(write_still=True)
    print(f"[render] {name}")


def report(name):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    triangles = 0
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.name == PREVIEW:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        triangles += len(mesh.loop_triangles)
        evaluated.to_mesh_clear()
    print(f"[stats] {name}: {triangles} triangles")


def export(name):
    """
    One file per material, each holding a single joined object.

    An FBX with several objects in it comes into Studio as a Model of
    MeshParts, and a SpecialMesh can only take one mesh. Joining first means
    one upload gives one mesh id. Splitting by material rather than joining
    everything keeps the two-tone pieces - a hat with a darker ridge, a cap
    with a leather band - which one mesh could not carry.
    """
    os.makedirs(EXPORT_DIR, exist_ok=True)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or obj.name == PREVIEW:
            continue
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)

    groups = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or obj.name == PREVIEW:
            continue
        material_name = obj.data.materials[0].name if obj.data.materials else "Untextured"
        groups.setdefault(material_name, []).append(obj)

    written = []
    for material_name, objects in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()

        joined = bpy.context.active_object
        joined.name = f"{name}_{material_name}"

        bpy.ops.object.select_all(action="DESELECT")
        joined.select_set(True)

        path = os.path.join(EXPORT_DIR, f"acc_{name}_{material_name}.fbx")
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
        written.append(f"acc_{name}_{material_name}")

    print(f"[export] {name}: " + ", ".join(written))


def main():
    for name, build in ACCESSORIES:
        clear_scene()
        build_materials()
        preview_head()
        build()
        setup_lighting()
        cam = setup_camera()
        setup_render()
        report(name)
        render(cam, name)
        export(name)


main()

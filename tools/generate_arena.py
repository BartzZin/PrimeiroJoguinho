"""Reproducible architectural kit; run with the project's portable Blender.

Generated TRELLIS ornaments are separate resources. Geometry here provides precise
architecture, watertight platforms, bridge arches, trim and reusable castle walls.
"""

import math
import random
from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "client-godot/assets/arena"
DEST.mkdir(parents=True, exist_ok=True)
random.seed(42)


def material(name, color, metal=0, roughness=0.65):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = roughness
    return mat


ivory = material("Celestial limestone", (0.65, 0.62, 0.53), 0, 0.72)
white = material("Polished marble", (0.81, 0.79, 0.69), 0.08, 0.33)
gold = material("Gilded brass", (0.64, 0.40, 0.11), 0.8, 0.28)
blue = material("Solar enamel", (0.025, 0.09, 0.28), 0.3, 0.35)
dark = material("Carved recess", (0.075, 0.11, 0.18), 0, 0.85)
rock = material("Island strata", (0.22, 0.27, 0.32), 0, 0.93)
grass = material("Alpine moss", (0.15, 0.28, 0.18), 0, 0.95)
roof = material("Azure glazed roof", (0.035, 0.13, 0.34), 0.25, 0.4)
window = material("Luminous glass", (0.32, 0.68, 0.88), 0.15, 0.2)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Dressed edges", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def box(name, pos, size, mat, bevel=0.03, yaw=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_euler.z = yaw
    return finish(obj, name, mat, bevel)


def cylinder(name, pos, radius, depth, mat, vertices=96, bevel=0.025):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=pos)
    return finish(bpy.context.object, name, mat, bevel)


def cone(name, pos, radius, depth, mat, top=0, vertices=48):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=top, depth=depth, location=pos)
    return finish(bpy.context.object, name, mat, 0.015)


def mesh(name, verts, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def ring(name, radius, width, z, mat, count=192):
    verts = []
    for height in [z - 0.015, z + 0.015]:
        for r in [radius - width / 2, radius + width / 2]:
            verts.extend((r * math.cos(a * math.tau / count), r * math.sin(a * math.tau / count), height) for a in range(count))
    faces = []
    for i in range(count):
        j = (i + 1) % count
        for a, b in [(0, count), (2 * count, 3 * count), (0, 2 * count), (count, 3 * count)]:
            faces.append((a + i, a + j, b + j, b + i))
    return mesh(name, verts, faces, mat)


def paving_sector(inner, outer, start, end):
    count = 8
    verts = []
    for z in [-0.64, -0.55]:
        for radius in [inner, outer]:
            verts.extend((radius * math.cos(start + (end-start)*i/count), radius * math.sin(start + (end-start)*i/count), z) for i in range(count+1))
    n = count+1
    faces = []
    for i in range(count):
        for a, b in [(0,n),(2*n,3*n),(0,2*n),(n,3*n)]:
            faces.append((a+i,a+i+1,b+i+1,b+i))
    faces.extend([(0,n,3*n,2*n),(count,n+count,3*n+count,2*n+count)])
    obj = mesh("Dressed paving slab",verts,faces,white)
    finish(obj,"Dressed paving slab",white,0.012)


def arch(name, center, radius, thickness, depth, mat, yaw=0):
    verts, faces = [], []
    steps = 24
    for y in [-depth / 2, depth / 2]:
        for r in [radius, radius + thickness]:
            for i in range(steps + 1):
                a = math.pi * i / steps
                verts.append((r * math.cos(a), y, r * math.sin(a)))
    n = steps + 1
    for i in range(steps):
        for a, b in [(0, n), (2 * n, 3 * n), (0, 2 * n), (n, 3 * n)]:
            faces.append((a + i, a + i + 1, b + i + 1, b + i))
    faces.extend([(0, n, 3 * n, 2 * n), (steps, n + steps, 3 * n + steps, 2 * n + steps)])
    obj = mesh(name, verts, faces, mat)
    obj.location = center
    obj.rotation_euler.z = yaw
    return obj


def export(name):
    # Joining by material keeps the architectural scene to a handful of draw calls.
    groups = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH":
            groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for objects in groups.values():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.join()
    bpy.ops.object.select_all(action="SELECT")
    output = ROOT / ".runtime/arena-prototypes" if name.endswith("_kit") else DEST
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output / f"{name}.glb"), export_format="GLB", use_selection=True)


def platform():
    clear()
    cylinder("Foundation", (0, 0, -1.3), 11.8, 1.4, ivory)
    cylinder("Lower cornice", (0, 0, -1.8), 12.05, 0.20, gold)
    cylinder("Recessed band", (0, 0, -0.87), 12.05, 0.24, blue)
    cylinder("Upper cornice", (0, 0, -0.70), 12.15, 0.14, gold)
    cylinder("Recessed mortar bed", (0, 0, -0.66), 12.0, 0.10, dark)
    radii = [4.4,6.8,8.8,10.4,11.95]
    for row in range(len(radii)-1):
        count = [32,40,48,56][row]
        shift = (row%2)*math.pi/count
        for sector in range(count):
            angle = sector*math.tau/count+shift
            paving_sector(radii[row]+0.012,radii[row+1]-0.012,angle+0.001,angle+math.tau/count-0.001)
    for r, w in [(6.9, 0.045), (7.15, 0.035), (9.9, 0.07), (10.1, 0.025), (11.85, 0.08)]:
        ring("Concentric gilded inlay", r, w, -0.558, gold)
    for i in range(48):
        a = i * math.tau / 48
        # Fine radial masonry seams and a ring of compass-like ornaments.
        r = 9.52
        box("Radial joint", (math.cos(a) * r, math.sin(a) * r, -0.565), (4.5, 0.014, 0.009), ivory, 0, a)
        if i % 3 == 0:
            r = 10.5
            obj = box("Compass lozenge", (math.cos(a) * r, math.sin(a) * r, -0.548), (0.28, 0.28, 0.025), gold, 0.015, a + math.pi / 4)
            obj.scale.x = 2.8
    for i in range(64):
        a = i * math.tau / 64
        x, y = math.cos(a) * 11.75, math.sin(a) * 11.75
        box("Balustrade post", (x, y, -0.08), (0.17, 0.17, 0.90), ivory, 0.025, a)
        if i % 8 != 3:
            box("Balustrade handrail", (x, y, 0.38), (0.21, 1.18, 0.12), gold, 0.025, a)
            mid = a+math.pi/64
            arch("Stone balustrade arch", (math.cos(mid)*11.75,math.sin(mid)*11.75,-0.32),0.42,0.09,0.13,ivory,mid+math.pi/2)
    # Complete underside, stepped like a suspended temple rather than a flat disk.
    cone("Underside vault", (0, 0, -3.0), 7.7, 3.0, ivory, top=11.65, vertices=96)
    cylinder("Underside medallion", (0, 0, -4.5), 7.8, 0.15, gold)
    cone("Suspended keystone", (0, 0, -5.7), 1.2, 2.4, dark, top=7.6, vertices=64)
    for i in range(32):
        a = i * math.tau / 32
        x, y = math.cos(a) * 11.85, math.sin(a) * 11.85
        box("Outer buttress", (x, y, -1.55), (0.38, 0.65, 1.7), ivory, 0.05, a)
        # Small blind arcade in the side wall, repeated all the way around.
        arch("Arcade molding", (math.cos(a) * 11.82, math.sin(a) * 11.82, -1.7), 0.40, 0.10, 0.10, gold, a + math.pi / 2)
    export("platform")


def bridge():
    clear()
    box("Bridge deck", (0, 0, 0), (18, 2.4, 0.35), white)
    for y in [-1.2, 1.2]:
        box("Parapet foot", (0, y, 0.36), (18, 0.25, 0.28), ivory)
        box("Parapet rail", (0, y, 1.1), (18, 0.25, 0.14), gold)
        for x in range(-8, 9, 2):
            box("Baluster", (x, y, 0.73), (0.22, 0.25, 0.75), ivory)
    for x in [-6, 0, 6]:
        arch("Bridge load arch", (x, 0, -2.7), 2.5, 0.5, 1.9, ivory)
        for dx in [-2.75, 2.75]:
            box("Bridge pier", (x + dx, 0, -2.6), (0.5, 1.9, 4.8), ivory)
    export("bridge")


def castle():
    clear()
    cylinder("Terrace", (0, 0, -0.25), 6.5, 0.5, white)
    ring("Terrace gold", 6.35, 0.12, 0.02, gold)
    box("Great hall", (0, 0, 2.8), (4.7, 3.6, 5.6), ivory, 0.08)
    box("Roof course", (0, 0, 5.7), (5.0, 3.9, 0.25), gold)
    for x, y, h, r in [(0, 0, 13, 1.6), (-2.6, -1.9, 8, 0.8), (2.6, -1.9, 8, 0.8), (-2.6, 1.9, 9, 0.8), (2.6, 1.9, 9, 0.8)]:
        cylinder("Tower shaft", (x, y, h / 2), r, h, ivory, vertices=32)
        for z in [0.3, h * 0.45, h * 0.8, h]:
            cylinder("Tower stringcourse", (x, y, z), r * 1.1, 0.15, gold, vertices=32)
        cone("Glazed spire", (x, y, h + r * 1.8), r * 1.2, r * 3.6, roof, vertices=32)
        cone("Golden finial", (x, y, h + r * 3.6 + 0.25), 0.12, 0.5, gold, vertices=12)
        for k in range(8):
            a = k * math.tau / 8
            for z in [h * 0.35, h * 0.65, h * 0.87]:
                px, py = x + math.cos(a) * r, y + math.sin(a) * r
                box("Lancet window", (px, py, z), (0.08, 0.32, 0.8), window, 0.015, a)
                cone("Buttress pinnacle", (x + math.cos(a) * r * 1.15, y + math.sin(a) * r * 1.15, h * 0.88), 0.10, 0.8, gold, vertices=8)
    for i in range(24):
        a = i * math.tau / 24
        x, y = math.cos(a) * 5.8, math.sin(a) * 5.8
        box("Curtain wall", (x, y, 0.75), (0.35, 1.7, 1.5), ivory, 0.04, a)
        box("Battlement", (x, y, 1.6), (0.5, 0.8, 0.25), gold, 0.03, a)
    export("castle_kit")


def island():
    clear()
    # Closed, irregular rings with explicit bottom cap; no invisible back faces.
    count = 48
    verts = []
    for radius, z in [(0.5, -9), (2.3, -6), (4.4, -3), (6.3, -0.65), (5.8, 0)]:
        for i in range(count):
            a = i * math.tau / count
            r = radius * (1 + random.uniform(-0.15, 0.15))
            verts.append((math.cos(a) * r, math.sin(a) * r, z + random.uniform(-0.25, 0.25)))
    faces = [tuple(reversed(range(count)))]
    for ring_id in range(4):
        for i in range(count):
            j = (i + 1) % count
            faces.append((ring_id * count + i, ring_id * count + j, (ring_id + 1) * count + j, (ring_id + 1) * count + i))
    faces.append(tuple(range(4 * count, 5 * count)))
    finish(mesh("Floating rock", verts, faces, rock), "Floating rock", rock, 0.06)
    cylinder("Grassy crown", (0, 0, -0.06), 5.5, 0.14, grass, vertices=48)
    export("island_kit")


for generator in [platform, bridge, castle, island]:
    generator()
print("Celestial architectural kit exported")

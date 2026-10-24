"""Repair, normal-bake and review a generated arena module, without editing TRELLIS.

Blender --background --python tools/prepare_arena_asset.py -- SOURCE NAME HEIGHT
Use HEIGHT < 0 for an island: its absolute value is width and the origin is the top.
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
source_path, asset_name, target_size = sys.argv[sys.argv.index("--") + 1 :][:3]
target_size = float(target_size)
dest = ROOT / "client-godot/assets/arena"
review = ROOT / ".runtime/arena-generation/reviews" / asset_name
review.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(Path(source_path).resolve()))
objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for obj in objects:
    transform = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    obj.data.transform(transform)
bpy.ops.object.select_all(action="DESELECT")
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.join()
high = bpy.context.object
high.name = asset_name + "_master"
bm = bmesh.new()
bm.from_mesh(high.data)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.0000001)
bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.000001)
boundary = [e for e in bm.edges if e.is_boundary]
noise_faces = set()
for edge in boundary:
    component = set(edge.link_faces)
    frontier = list(component)
    while frontier and len(component) <= 8:
        face = frontier.pop()
        for linked_edge in face.edges:
            for neighbor in linked_edge.link_faces:
                if neighbor not in component:
                    component.add(neighbor)
                    frontier.append(neighbor)
    if len(component) <= 8:
        noise_faces.update(component)
if noise_faces:
    bmesh.ops.delete(bm, geom=list(noise_faces), context="FACES")
    unused = [v for v in bm.verts if not v.link_faces]
    if unused:
        bmesh.ops.delete(bm, geom=unused, context="VERTS")
boundary = [e for e in bm.edges if e.is_boundary]
if boundary:
    bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
report = {"source": Path(source_path).name, "filled_boundary_edges": len(boundary),
          "discarded_isolated_noise_faces": len(noise_faces),
          "boundary_edges": sum(e.is_boundary for e in bm.edges),
          "nonmanifold_edges": sum(not e.is_manifold for e in bm.edges),
          "master_triangles": sum(len(f.verts) - 2 for f in bm.faces)}
bm.to_mesh(high.data)
bm.free()
if report["boundary_edges"] or report["nonmanifold_edges"]:
    raise RuntimeError("Asset still has topological defects: " + json.dumps(report))
coords = [v.co.copy() for v in high.data.vertices]
minimum = Vector(tuple(min(v[i] for v in coords) for i in range(3)))
maximum = Vector(tuple(max(v[i] for v in coords) for i in range(3)))
extent = maximum - minimum
factor = abs(target_size) / (extent.z if target_size > 0 else max(extent.x, extent.y))
center = (minimum + maximum) * 0.5
center.z = minimum.z if target_size > 0 else maximum.z
for vertex in high.data.vertices:
    vertex.co = (vertex.co - center) * factor
for face in high.data.polygons:
    face.use_smooth = True
original = ROOT / "art/arena/originals" / (asset_name + "-repaired.glb")
bpy.ops.export_scene.gltf(filepath=str(original), export_format="GLB", use_selection=True)
low = high.copy()
low.data = high.data.copy()
bpy.context.collection.objects.link(low)
low.name = asset_name
high.select_set(False)
low.select_set(True)
bpy.context.view_layer.objects.active = low
budget = 40000 if asset_name.startswith("castle") else 24000
modifier = low.modifiers.new("Runtime detail reduction", "DECIMATE")
modifier.ratio = min(1.0, budget / len(low.data.polygons))
modifier.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=modifier.name)
bm = bmesh.new()
bm.from_mesh(low.data)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.000001)
bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.00001)
visited = set()
isolated = []
for face in bm.faces:
    if face in visited:
        continue
    component = [face]
    visited.add(face)
    frontier = [face]
    while frontier:
        current = frontier.pop()
        for edge in current.edges:
            for neighbor in edge.link_faces:
                if neighbor not in visited:
                    visited.add(neighbor)
                    frontier.append(neighbor)
                    component.append(neighbor)
    if len(component) <= 8 and sum(f.calc_area() for f in component) < 0.01:
        isolated.extend(component)
if isolated:
    bmesh.ops.delete(bm, geom=isolated, context="FACES")
    unused = [vertex for vertex in bm.verts if not vertex.link_faces]
    if unused:
        bmesh.ops.delete(bm, geom=unused, context="VERTS")
report["runtime_discarded_noise_faces"] = len(isolated)
boundary = [edge for edge in bm.edges if edge.is_boundary]
if boundary:
    bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
report["runtime_boundary_edges"] = sum(edge.is_boundary for edge in bm.edges)
report["runtime_nonmanifold_edges"] = sum(not edge.is_manifold for edge in bm.edges)
if report["runtime_boundary_edges"] or report["runtime_nonmanifold_edges"]:
    raise RuntimeError("Reduction introduced a geometric defect: " + json.dumps(report))
bm.to_mesh(low.data)
bm.free()
report["runtime_triangles"] = sum(len(p.vertices) - 2 for p in low.data.polygons)
texture_size = 2048 if asset_name == "island" else 4096
normal = bpy.data.images.new(asset_name + "_normal", width=texture_size, height=texture_size, alpha=False)
normal.colorspace_settings.name = "Non-Color"
for index, old_material in enumerate(low.data.materials):
    mat = old_material.copy()
    low.data.materials[index] = mat
    nodes = mat.node_tree.nodes
    target = nodes.new("ShaderNodeTexImage")
    target.image = normal
    nodes.active = target
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 1
scene.render.threads_mode = "FIXED"
scene.render.threads = 8
scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.015 * abs(target_size)
scene.render.bake.max_ray_distance = 0.06 * abs(target_size)
scene.render.bake.margin = 24
high.select_set(True)
print("BAKING_NORMAL", asset_name, flush=True)
bpy.ops.object.bake(type="NORMAL")
normal.filepath_raw = str(review / "normal.png")
normal.file_format = "PNG"
normal.save()
for mat in low.data.materials:
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    tex = next(n for n in nodes if n.type == "TEX_IMAGE" and n.image == normal)
    mapping = nodes.new("ShaderNodeNormalMap")
    links.new(tex.outputs["Color"], mapping.inputs["Color"])
    links.new(mapping.outputs["Normal"], nodes.get("Principled BSDF").inputs["Normal"])
high.select_set(False)
bpy.data.objects.remove(high, do_unlink=True)
low.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(dest / (asset_name + ".glb")), export_format="GLB", use_selection=True)
report["normal_texture"] = texture_size
report["target_size"] = target_size
(ROOT / "art/arena" / (asset_name + "-preparation.json")).write_text(json.dumps(report, indent=2), encoding="utf-8")
# Twelve actual material renders, including back, top and underside.
scene.render.engine = "CYCLES"
scene.cycles.samples = 12
scene.render.resolution_x = 384
scene.render.resolution_y = 384
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("Black studio")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.045, 0.045, 0.045, 1)
for location, energy, size in [((4,-5,7),1800,5),((-4,-2,4),1000,4),((0,4,6),1600,3)]:
    light = bpy.data.lights.new("Studio", "AREA")
    light.energy, light.shape, light.size = energy * (abs(target_size) / 3) ** 2, "DISK", size * abs(target_size) / 3
    obj = bpy.data.objects.new("Studio", light)
    scene.collection.objects.link(obj)
    obj.location = Vector(location) * abs(target_size) / 3
    obj.rotation_euler = (Vector((0,0,target_size*0.4)) - obj.location).to_track_quat("-Z","Y").to_euler()
camera_data = bpy.data.cameras.new("Review camera")
camera = bpy.data.objects.new("Review camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "ORTHO"
camera_data.ortho_scale = abs(target_size)*1.35
target = Vector((0,0,target_size*0.5 if target_size > 0 else -abs(target_size)*0.3))
sheet = np.zeros((384*3,384*4,4), np.float32)
for i in range(12):
    elevation = math.radians(15 if i < 8 else (70 if i < 10 else -65))
    azimuth = i*math.tau/8
    camera.location = target + Vector((math.cos(azimuth)*math.cos(elevation),math.sin(azimuth)*math.cos(elevation),math.sin(elevation)))*abs(target_size)*3
    camera.rotation_euler = (target-camera.location).to_track_quat("-Z","Y").to_euler()
    scene.render.filepath = str(review / f"view-{i:02}.png")
    bpy.ops.render.render(write_still=True)
    rendered = bpy.data.images.load(scene.render.filepath)
    pixels = np.asarray(rendered.pixels[:], dtype=np.float32).reshape(384,384,4)
    sheet[(2-i//4)*384:(3-i//4)*384,(i%4)*384:(i%4+1)*384] = pixels
    bpy.data.images.remove(rendered)
contact = bpy.data.images.new("Twelve views", width=1536, height=1152, alpha=True)
contact.pixels.foreach_set(sheet.ravel())
contact.filepath_raw = str(ROOT / "art/arena" / (asset_name+"-12-views.png"))
contact.file_format = "PNG"
contact.save()
print("PREPARED", json.dumps(report), flush=True)

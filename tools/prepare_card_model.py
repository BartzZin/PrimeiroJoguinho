"""Prepare one reusable card from the official TRELLIS silhouette (portable Blender)."""

import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.geometry import convex_hull_2d

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[sys.argv.index('--') + 1])
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(source))
points = [obj.matrix_world @ vertex.co for obj in bpy.context.scene.objects
          if obj.type == 'MESH' for vertex in obj.data.vertices]
low = [min(p[i] for p in points) for i in range(3)]
high = [max(p[i] for p in points) for i in range(3)]
print('SOURCE BOUNDS', low, high)
axes = sorted(range(3), key=lambda i: high[i] - low[i])
thickness, horizontal, vertical = axes
projected = [Vector(((p[horizontal] - (low[horizontal] + high[horizontal]) / 2) / (high[horizontal] - low[horizontal]) * .98,
                     (p[vertical] - (low[vertical] + high[vertical]) / 2) / (high[vertical] - low[vertical]) * 1.55)) for p in points]
outline = [projected[i] for i in convex_hull_2d(projected)]
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def material(name, color, metallic=0):
    paint = bpy.data.materials.new(name)
    paint.diffuse_color = (*color, 1)
    paint.use_nodes = True
    shader = paint.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = .32
    return paint


gold = material('Shared antique gold frame', (.65, .37, .09), .65)
violet = material('Shared violet card body', (.09, .025, .19), .2)
count = len(outline)
vertices = [(p.x, y, p.y) for y in [-.035, .035] for p in outline]
faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
faces += [(i, (i + 1) % count, (i + 1) % count + count, i + count) for i in range(count)]
mesh = bpy.data.meshes.new('Modelador3d silhouette')
mesh.from_pydata(vertices, [], faces)
mesh.update()
body = bpy.data.objects.new('CardBody', mesh)
bpy.context.collection.objects.link(body)
body.data.materials.append(violet)
bpy.context.view_layer.objects.active = body
body.select_set(True)
bevel = body.modifiers.new('Physical rounded edge', 'BEVEL')
bevel.width = .012
bevel.segments = 3
bpy.ops.object.modifier_apply(modifier=bevel.name)
body.select_set(False)

# Shared raised rim: never bake a spell symbol into this geometry.
rim_vertices = [(p.x * scale, y, p.y * scale) for scale, y in [(1, -.038), (.91, -.055)] for p in outline]
rim_mesh = bpy.data.meshes.new('Shared raised rim')
rim_mesh.from_pydata(rim_vertices, [], [(i, (i + 1) % count, (i + 1) % count + count, i + count) for i in range(count)])
rim_mesh.update()
rim = bpy.data.objects.new('GoldFrame', rim_mesh)
bpy.context.collection.objects.link(rim)
rim.data.materials.append(gold)

# One replaceable material slot; Godot assigns one of twelve face images at runtime.
art = bpy.data.meshes.new('Replaceable face UV')
art.from_pydata([(-.448, -.057, -.71), (.448, -.057, -.71), (.448, -.057, .71), (-.448, -.057, .71)], [], [(0, 1, 2, 3)])
art.uv_layers.new(name='UVMap')
for polygon in art.polygons:
    for loop, uv in zip(polygon.loop_indices, [(0, 0), (1, 0), (1, 1), (0, 1)], strict=True):
        art.uv_layers.active.data[loop].uv = uv
art.update()
artwork = bpy.data.objects.new('Artwork', art)
bpy.context.collection.objects.link(artwork)
artwork.data.materials.append(material('Replaceable artwork', (.5, .15, .8)))
destination = root / 'client-godot/assets/cards/models/card.glb'
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(destination), export_format='GLB', export_yup=True)
for obj in [body, rim, artwork]:
    obj.data.calc_loop_triangles()
report = {'source': 'art/cards/source/card-original.glb', 'source_bounds': [low, high],
          'shared_model': 'client-godot/assets/cards/models/card.glb', 'models': 1,
          'triangles': sum(len(obj.data.loop_triangles) for obj in [body, rim, artwork]),
          'dimensions': [0.98, 1.55, 0.09], 'face_node': 'Artwork',
          'preparation': 'Extract generated silhouette, normalize, remove spell-specific relief, add shared rim and replaceable UV face.'}
(root / 'art/cards/preparation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')

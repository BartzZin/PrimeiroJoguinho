"""Beveled board frame, generated with the portable Blender in background mode."""

from pathlib import Path

import bpy

DESTINATION = Path(__file__).resolve().parents[1] / "client-godot/assets/board/frame.glb"
DESTINATION.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def paint(name, color, metallic, roughness):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return material


navy = paint("Midnight enamel", (0.018, 0.029, 0.048), 0.35, 0.32)
gold = paint("Brushed brass", (0.56, 0.35, 0.12), 0.72, 0.3)
slate = paint("Slate surround", (0.025, 0.042, 0.068), 0.2, 0.48)


def slab(name, dimensions, location, material, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    modifier = obj.modifiers.new("Rounded machined edges", "BEVEL")
    modifier.width = bevel
    modifier.segments = 3
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.modifiers.new("Weighted surface normals", "WEIGHTED_NORMAL")
    return obj


slab("Plinth", (8.8, 8.8, 0.18), (0, 0, -0.38), navy, 0.07)
slab("Brass reveal", (8.7, 8.7, 0.06), (0, 0, -0.26), gold, 0.02)
slab("Playing surround", (8.56, 8.56, 0.22), (0, 0, -0.12), slate, 0.035)
for edge in (-1, 1):
    slab("Edge inlay", (8.48, 0.025, 0.018), (0, edge * 4.24, 0.007), gold, 0.006)
    slab("Edge inlay", (0.025, 8.48, 0.018), (edge * 4.24, 0, 0.007), gold, 0.006)
    for other in (-1, 1):
        corner = slab(
            "Corner inlay", (0.14, 0.14, 0.022), (edge * 4.14, other * 4.14, 0.012), gold
        )
        corner.rotation_euler.z = 0.785398

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=str(DESTINATION), export_format="GLB", use_selection=True)
print("Beveled board frame exported to", DESTINATION)

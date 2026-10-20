"""Original procedural miniatures. Run with the portable Blender, no external assets."""

import math
from pathlib import Path

import bpy

DESTINATION = Path(__file__).resolve().parents[1] / "client-godot/assets/models"
DESTINATION.mkdir(parents=True, exist_ok=True)


def cylinder(radius, depth, z, top=None, x=0):
    bpy.ops.mesh.primitive_cone_add(
        vertices=32,
        radius1=radius,
        radius2=top if top is not None else radius,
        depth=depth,
        location=(x, 0, z),
    )
    return bpy.context.object


def sphere(radius, z, scale=(1, 1, 1), x=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=radius, location=(x, 0, z))
    obj = bpy.context.object
    obj.scale = scale
    return obj


for kind in ("pawn", "rook", "knight", "bishop", "queen", "king"):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    cylinder(0.34, 0.1, 0.05)
    cylinder(0.3, 0.09, 0.145, top=0.27)
    height = {
        "pawn": 0.48,
        "rook": 0.64,
        "knight": 0.65,
        "bishop": 0.75,
        "queen": 0.85,
        "king": 0.94,
    }[kind]
    cylinder(0.24, height - 0.2, (height + 0.2) / 2, top=0.13)
    cylinder(0.23, 0.07, height)
    if kind == "pawn":
        sphere(0.2, height + 0.17)
    elif kind == "rook":
        cylinder(0.27, 0.17, height + 0.1)
        for angle in range(0, 360, 90):
            bpy.ops.mesh.primitive_cube_add(
                size=0.14,
                location=(
                    0.2 * math.cos(math.radians(angle)),
                    0.2 * math.sin(math.radians(angle)),
                    height + 0.23,
                ),
            )
    elif kind == "knight":
        sphere(0.23, height + 0.13, (0.75, 0.7, 1.4))
        sphere(0.21, height + 0.32, (1.3, 0.75, 0.75), x=0.12)
        cylinder(0.07, 0.22, height + 0.53, top=0.0, x=-0.03)
    elif kind == "bishop":
        sphere(0.21, height + 0.2, (0.85, 0.85, 1.35))
        sphere(0.065, height + 0.48)
    elif kind == "queen":
        cylinder(0.16, 0.22, height + 0.13, top=0.27)
        for angle in range(0, 360, 60):
            obj = sphere(0.06, height + 0.31)
            obj.location.x = 0.23 * math.cos(math.radians(angle))
            obj.location.y = 0.23 * math.sin(math.radians(angle))
        sphere(0.08, height + 0.39)
    else:
        sphere(0.18, height + 0.13)
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, height + 0.42))
        bpy.context.object.scale = (0.07, 0.07, 0.23)
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, height + 0.46))
        bpy.context.object.scale = (0.23, 0.07, 0.07)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = next(
        obj for obj in bpy.context.scene.objects if obj.type == "MESH"
    )
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = kind
    bevel = obj.modifiers.new("soft_edges", "BEVEL")
    bevel.width = 0.015
    bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.export_scene.gltf(
        filepath=str(DESTINATION / f"{kind}.glb"),
        export_format="GLB",
        use_selection=True,
    )
print("Six original miniatures exported to", DESTINATION)

"""Audit exported runtime GLBs with Blender, including tangent normal textures."""

import json
from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[1]
reports = {}
for name in ["pillar", "castle", "island", "crystal"]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = ROOT / "client-godot/assets/arena" / (name + ".glb")
    bpy.ops.import_scene.gltf(filepath=str(path))
    result = {"triangles": 0, "boundary_edges": 0, "nonmanifold_edges": 0, "degenerate_faces": 0, "normal_maps": 0}
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.000001)
        result["triangles"] += sum(len(face.verts) - 2 for face in bm.faces)
        result["boundary_edges"] += sum(e.is_boundary for e in bm.edges)
        result["nonmanifold_edges"] += sum(not e.is_manifold for e in bm.edges)
        result["degenerate_faces"] += sum(face.calc_area() < 1e-12 for face in bm.faces)
        bm.free()
        for mat in obj.data.materials:
            result["normal_maps"] += sum(n.type == "NORMAL_MAP" for n in mat.node_tree.nodes)
    reports[name] = result
    print("AUDIT", name, json.dumps(result), flush=True)
(ROOT / "art/arena/runtime-audit.json").write_text(json.dumps(reports, indent=2), encoding="utf-8")
if any(r["boundary_edges"] or r["nonmanifold_edges"] or r["degenerate_faces"] or not r["normal_maps"] for r in reports.values()):
    raise RuntimeError("Runtime GLB audit failed")

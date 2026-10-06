# ============================================================
#  PYTHA glTF Importer for Blender 4.2+ / 5.x
#  File > Import > PYTHA (.glb/.gltf)
#
#  Diagnostic output: Window > Toggle System Console (Windows)
#
#  What it does, on top of Blender's own glTF importer:
#   * PYTHA's group tree (Kitchen > Base > Carcass / Externals > Drawer_1 ...)
#     becomes a nested COLLECTION tree instead of 100+ empties.
#   * Part names come through exactly as named in PYTHA. Blender's own
#     importer mangles names like "0948_L204,H27,W18.5" into
#     "0948_L204,H27,W18.001" (it reads ".5" as a duplicate-name suffix);
#     here every object also gets the exact name in custom property
#     "pytha_name".
#   * Layers and pens: PYTHA's glTF export drops them. Run the BCW Export
#     Tags plugin in PYTHA ("Tag parts for export") before exporting; the
#     tag it adds to each part name, " {L<layer>:<layer name> P<pen>}", is
#     read here, removed from the name, stored as custom properties
#     "pytha_layer", "pytha_layer_name", "pytha_pen", and each part is ALSO
#     linked into "Layers / <layer>" (and optionally "Pens / Pen <n>")
#     collections - so you can browse by group or by layer.
#     Parts without a material arrive with a material named "Pen <n>";
#     that pen number is recorded even without tags.
#   * Material library (optional): any imported material whose name matches
#     a material in a chosen .blend is replaced by the library material
#     (bulk "assign my own materials" in one step).
#   * Clean-up from the Cabinet Vision importer: merge vertices by distance
#     (glTF splits every part per material, duplicating seam vertices) and
#     mark hard edges as UV seams.
#
#  CHANGELOG
#  1.0.0 - first version (2026-10-06), tested against a PYTHA V26 GLB export
#          of a BCW Cabinet Wizard kitchen.
# ============================================================

bl_info = {
    "name": "PYTHA glTF Importer",
    "author": "Brassington Caseworks",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "File > Import > PYTHA (.glb/.gltf)",
    "description": "Import PYTHA glTF exports with the group tree as collections, exact part names, layers/pens (via BCW Export Tags) and material library swap",
    "category": "Import-Export",
}

import os
import re
import json
import math
import struct
import tempfile

import bpy
import bmesh
from bpy.props import StringProperty, BoolProperty, FloatProperty
from bpy_extras.io_utils import ImportHelper
from bpy.types import Operator

VERBOSE = True

# " {L12:Doors P3}" at the end of a part name (written by the BCW Export Tags PYTHA plugin)
TAG_RE = re.compile(r"\s*\{L(-?\d+):(.*?) P(-?\d+)\}\s*$")
PEN_MAT_RE = re.compile(r"^Pen (\d+)$")
TOKEN = "PYTHAN_%d"


def _log(*args):
    if VERBOSE:
        print("[PYTHA glTF]", *args)


# ── glTF / GLB reading and the temporary renamed copy ───────────────────────

def _read_gltf(path):
    """Return (json_dict, kind, bin_chunk_or_None)."""
    with open(path, "rb") as f:
        head = f.read(4)
        f.seek(0)
        if head == b"glTF":
            data = f.read()
            _magic, _ver, _length = struct.unpack_from("<4sII", data, 0)
            off = 12
            js = None
            binc = None
            while off < len(data):
                clen, ctype = struct.unpack_from("<I4s", data, off)
                chunk = data[off + 8: off + 8 + clen]
                if ctype == b"JSON":
                    js = json.loads(chunk.decode("utf-8"))
                elif ctype == b"BIN\x00":
                    binc = chunk
                off += 8 + clen
            return js, "glb", binc
        return json.loads(f.read().decode("utf-8")), "gltf", None


def _write_glb(path, js, binc):
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    total = 12 + 8 + len(jb) + (8 + len(binc) if binc is not None else 0)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(jb), b"JSON"))
        f.write(jb)
        if binc is not None:
            f.write(struct.pack("<I4s", len(binc), b"BIN\x00"))
            f.write(binc)


def _tokenized_copy(path, js, kind, binc):
    """Write a copy whose node names are unique tokens, so every Blender object
    created by the stock importer maps back to exactly one glTF node."""
    js2 = json.loads(json.dumps(js))
    for i, n in enumerate(js2.get("nodes", [])):
        n["name"] = TOKEN % i
    if kind == "glb":
        fd, tmp = tempfile.mkstemp(suffix=".glb")
        os.close(fd)
        _write_glb(tmp, js2, binc)
    else:
        # .gltf: keep it next to the original so relative .bin/texture URIs resolve
        d = os.path.dirname(os.path.abspath(path))
        fd, tmp = tempfile.mkstemp(suffix=".gltf", dir=d)
        os.close(fd)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(js2, f)
    return tmp


# ── import ──────────────────────────────────────────────────────────────────

class PythaImport:
    def __init__(self, filepath, opts, report=None):
        self.filepath = filepath
        self.o = opts
        self.report = report or (lambda level, msg: None)
        self.parts = []          # (object, node_index)
        self.groups = {}         # node_index -> collection
        self.stats = {}

    def run(self, context):
        js, kind, binc = _read_gltf(self.filepath)
        nodes = js.get("nodes", [])
        self.nodes = nodes
        gen = js.get("asset", {}).get("generator", "?")
        _log("file:", self.filepath, "| generator:", gen, "| nodes:", len(nodes))
        if not gen.upper().startswith("PYTHA"):
            self.report({"WARNING"}, "Not a PYTHA export (generator '%s') - importing anyway" % gen)

        tmp = _tokenized_copy(self.filepath, js, kind, binc)
        before = set(bpy.data.objects)
        try:
            bpy.ops.import_scene.gltf(filepath=tmp)
        finally:
            try:
                os.remove(tmp)
            except OSError:
                pass
        new_objs = [o for o in bpy.data.objects if o not in before]

        by_node = {}
        for ob in new_objs:
            m = re.match(r"^PYTHAN_(\d+)", ob.name)
            if m:
                by_node[int(m.group(1))] = ob

        # parents per node (glTF tree), roots from the scene
        parent = {}
        for i, n in enumerate(nodes):
            for c in n.get("children", []):
                parent[c] = i
        scene_roots = js.get("scenes", [{}])[js.get("scene", 0)].get("nodes", [])

        base = os.path.splitext(os.path.basename(self.filepath))[0]
        root_col = bpy.data.collections.new("PYTHA " + base)
        context.scene.collection.children.link(root_col)
        self.root_col = root_col

        # collections for group nodes (nodes with children and no mesh, or with children)
        def group_col(i):
            if i in self.groups:
                return self.groups[i]
            p = parent.get(i)
            parent_col = group_col(p) if p is not None else root_col
            col = bpy.data.collections.new(nodes[i].get("name") or "Group")
            col["pytha_name"] = nodes[i].get("name") or ""
            parent_col.children.link(col)
            self.groups[i] = col
            return col

        # build parts
        for i, ob in sorted(by_node.items()):
            n = nodes[i]
            if ob.type != "MESH":
                continue
            mw = ob.matrix_world.copy()
            ob.parent = None
            ob.matrix_world = mw
            raw = n.get("name") or "Part"
            name, layer, layer_name, pen = self._parse_tag(raw)
            name = name or "Part"
            ob["pytha_name"] = name
            if layer is not None:
                ob["pytha_layer"] = layer
                ob["pytha_layer_name"] = layer_name
            if pen is not None:
                ob["pytha_pen"] = pen
            ob.name = name
            ob.data.name = name
            # group membership
            p = parent.get(i)
            target = group_col(p) if p is not None else root_col
            for c in list(ob.users_collection):
                c.objects.unlink(ob)
            target.objects.link(ob)
            # a mesh node can itself have children (PYTHA rarely does this) - its
            # children then go into a collection named after it
            self.parts.append((ob, i))

        # pens from "Pen <n>" materials (parts without a PYTHA material)
        for ob, _ in self.parts:
            if "pytha_pen" in ob:
                continue
            for slot in ob.material_slots:
                if slot.material:
                    m = PEN_MAT_RE.match(re.sub(r"\.\d{3}$", "", slot.material.name))
                    if m:
                        ob["pytha_pen"] = int(m.group(1))
                        break

        # remove the empties the stock importer made for groups
        empties = [o for o in by_node.values() if o.type == "EMPTY"]
        for e in empties:
            bpy.data.objects.remove(e, do_unlink=True)

        self.stats["parts"] = len(self.parts)
        self.stats["groups"] = len(self.groups)
        self.stats["empties_removed"] = len(empties)
        self._layer_and_pen_collections()
        if self.o.get("material_library"):
            self._swap_materials(self.o["material_library"])
        if self.o.get("merge_by_distance"):
            self._merge_by_distance(self.o.get("merge_distance", 0.0001))
        if self.o.get("mark_hard_edges"):
            self._mark_hard_edge_seams()
        return self.stats

    @staticmethod
    def _parse_tag(raw):
        m = TAG_RE.search(raw)
        if not m:
            return raw, None, None, None
        return raw[:m.start()], int(m.group(1)), m.group(2), int(m.group(3))

    def _layer_and_pen_collections(self):
        tagged = [ob for ob, _ in self.parts if "pytha_layer" in ob]
        self.stats["tagged_parts"] = len(tagged)
        if tagged and self.o.get("layer_collections", True):
            lay_root = bpy.data.collections.new("Layers")
            self.root_col.children.link(lay_root)
            cols = {}
            for ob in tagged:
                key = (ob["pytha_layer"], ob.get("pytha_layer_name", ""))
                if key not in cols:
                    label = "Layer %d" % key[0] + (" - %s" % key[1] if key[1] else "")
                    c = bpy.data.collections.new(label)
                    c["pytha_layer"] = key[0]
                    lay_root.children.link(c)
                    cols[key] = c
                cols[key].objects.link(ob)
            self.stats["layers"] = len(cols)
        pens = [ob for ob, _ in self.parts if "pytha_pen" in ob]
        if pens and self.o.get("pen_collections", False):
            pen_root = bpy.data.collections.new("Pens")
            self.root_col.children.link(pen_root)
            cols = {}
            for ob in pens:
                p = ob["pytha_pen"]
                if p not in cols:
                    c = bpy.data.collections.new("Pen %d" % p)
                    pen_root.children.link(c)
                    cols[p] = c
                cols[p].objects.link(ob)
            self.stats["pens"] = len(cols)
        if not tagged:
            _log("no layer/pen tags found - run 'Tag parts for export' (BCW Export Tags) in PYTHA before exporting to get layers")

    def _swap_materials(self, lib_path):
        lib_path = bpy.path.abspath(lib_path)
        if not os.path.isfile(lib_path):
            self.report({"WARNING"}, "Material library not found: %s" % lib_path)
            return
        used = set()
        for ob, _ in self.parts:
            for s in ob.material_slots:
                if s.material:
                    used.add(s.material)
        def base(n):
            # "VP-1.001" -> "VP-1" (Blender's duplicate suffix only: a dot + exactly 3 digits)
            return re.sub(r"\.\d{3}$", "", n)
        with bpy.data.libraries.load(lib_path, link=False) as (src, dst):
            lib_names = set(src.materials)
            wanted = sorted({base(m.name) for m in used} & lib_names)
            dst.materials = list(wanted)
        # appended materials get renamed on a name clash ("VP-1" -> "VP-1.001"), so map by request order
        loaded = {name: m for name, m in zip(wanted, dst.materials) if m is not None}
        swapped = 0
        for m in used:
            new = loaded.get(base(m.name))
            if new is not None and new is not m:
                old_name = base(m.name)
                m.user_remap(new)
                bpy.data.materials.remove(m)
                new.name = old_name
                swapped += 1
        self.stats["materials_swapped"] = swapped
        _log("material library: %d of %d imported materials replaced from %s" % (swapped, len(used), lib_path))

    def _merge_by_distance(self, dist):
        removed = 0
        for ob, _ in self.parts:
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            n0 = len(bm.verts)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
            if len(bm.verts) != n0:
                removed += n0 - len(bm.verts)
                bm.to_mesh(ob.data)
                ob.data.update()
            bm.free()
        self.stats["verts_welded"] = removed

    def _mark_hard_edge_seams(self, angle_limit=math.radians(40.0)):
        n = 0
        for ob, _ in self.parts:
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            for e in bm.edges:
                if len(e.link_faces) == 2 and e.calc_face_angle() > angle_limit:
                    e.seam = True
                    n += 1
            bm.to_mesh(ob.data)
            bm.free()
            ob.data.update()
        self.stats["seams_marked"] = n


class IMPORT_OT_pytha_gltf(Operator, ImportHelper):
    """Import a PYTHA glTF export (.glb / .gltf)"""
    bl_idname = "import_scene.pytha_gltf"
    bl_label = "Import PYTHA glTF"
    bl_options = {"REGISTER", "UNDO"}

    filename_ext = ".glb"
    filter_glob: StringProperty(default="*.glb;*.gltf", options={"HIDDEN"})

    layer_collections: BoolProperty(
        name="Layer Collections",
        description="Also link every tagged part into 'Layers / Layer <n>' collections (needs BCW Export Tags in PYTHA before export)",
        default=True)
    pen_collections: BoolProperty(
        name="Pen Collections",
        description="Also link every part with a known pen into 'Pens / Pen <n>' collections",
        default=False)
    material_library: StringProperty(
        name="Material Library",
        description="Optional .blend file: imported materials with the same name are replaced by the library's material",
        default="", subtype="FILE_PATH")
    merge_by_distance: BoolProperty(
        name="Merge Vertices by Distance",
        description="Weld the duplicate vertices glTF leaves where a part's faces change material",
        default=True)
    merge_distance: FloatProperty(
        name="Distance", default=0.0001, min=0.0, precision=5, unit="LENGTH")
    mark_hard_edges: BoolProperty(
        name="Mark Hard Edges as Seams",
        description="Mark edges where faces meet at more than ~40 degrees as UV seams",
        default=True)

    def execute(self, context):
        import time
        t0 = time.perf_counter()
        try:
            imp = PythaImport(self.filepath, {
                "layer_collections": self.layer_collections,
                "pen_collections": self.pen_collections,
                "material_library": self.material_library,
                "merge_by_distance": self.merge_by_distance,
                "merge_distance": self.merge_distance,
                "mark_hard_edges": self.mark_hard_edges,
            }, report=self.report)
            st = imp.run(context)
        except Exception as exc:
            import traceback
            traceback.print_exc()
            self.report({"ERROR"}, "PYTHA import failed: %s" % exc)
            return {"CANCELLED"}
        msg = "PYTHA import: %d parts, %d groups" % (st.get("parts", 0), st.get("groups", 0))
        if st.get("tagged_parts"):
            msg += ", %d layers" % st.get("layers", 0)
        else:
            msg += ", no layer tags"
        if "materials_swapped" in st:
            msg += ", %d materials from library" % st["materials_swapped"]
        msg += " (%.1fs)" % (time.perf_counter() - t0)
        _log(msg, st)
        self.report({"INFO"}, msg)
        return {"FINISHED"}

    def draw(self, context):
        layout = self.layout
        layout.prop(self, "layer_collections")
        layout.prop(self, "pen_collections")
        layout.prop(self, "material_library")
        layout.prop(self, "merge_by_distance")
        row = layout.row()
        row.enabled = self.merge_by_distance
        row.prop(self, "merge_distance")
        layout.prop(self, "mark_hard_edges")


def _menu(self, context):
    self.layout.operator(IMPORT_OT_pytha_gltf.bl_idname, text="PYTHA (.glb/.gltf)")


def register():
    bpy.utils.register_class(IMPORT_OT_pytha_gltf)
    bpy.types.TOPBAR_MT_file_import.append(_menu)


def unregister():
    bpy.types.TOPBAR_MT_file_import.remove(_menu)
    bpy.utils.unregister_class(IMPORT_OT_pytha_gltf)


if __name__ == "__main__":
    register()

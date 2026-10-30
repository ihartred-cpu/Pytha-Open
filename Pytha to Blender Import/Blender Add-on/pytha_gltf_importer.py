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
#     Tags plugin in PYTHA ("Export tags") before exporting; the
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
#  HOW THE WHOLE FILE FITS TOGETHER (read this before the code below):
#   1. _read_gltf / _write_glb / _tokenized_copy: glTF/GLB is just JSON (plus
#      an optional binary blob for mesh data). PYTHA writes each node's own
#      name into the glTF JSON, but Blender's STOCK glTF importer can rename
#      objects on import (to dodge name collisions) and gives no reliable way
#      to map a resulting Blender object back to the glTF node it came from.
#      The fix used here: before handing the file to Blender's importer, make
#      a TEMPORARY COPY where every node's name is overwritten with a unique
#      token ("PYTHAN_0", "PYTHAN_1", ...). Blender then can't rename them
#      into collision, and this file can match each new Blender object back
#      to its original node by that token - and only then restore the real
#      PYTHA name (optionally minus its layer/pen tag).
#   2. PythaImport.run(): orchestrates the whole import - write the
#      tokenized copy, call Blender's bpy.ops.import_scene.gltf, then walk
#      the resulting objects and the glTF node tree together to rebuild
#      PYTHA's group structure as nested Blender collections, restore real
#      names, and pull out layer/pen data from the Export Tags.
#   3. The rest of PythaImport's methods are the optional clean-up/extra
#      steps (layer & pen collections, material library swap, vertex
#      welding, hard-edge UV seams), each one individually toggleable from
#      the operator's options.
#   4. IMPORT_OT_pytha_gltf: the Blender Operator (what actually shows up
#      under File > Import) - just wires up the options UI and calls
#      PythaImport.
#   5. register()/unregister() + _menu: standard Blender add-on boilerplate
#      that adds/removes the menu entry.
#
#  CHANGELOG
#  1.0.0 - first version (2026-10-06), tested against a PYTHA V26 GLB export
#          of a BCW Kitchen Wizard kitchen.
# ============================================================

# Blender's add-on manifest: this dict is what Blender reads to show the
# add-on in Edit > Preferences > Add-ons (name, author, minimum Blender
# version, where its menu entry lives, and its one-line description).
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
# Matches the material name PYTHA's glTF export gives a part that has NO
# real material assigned ("Pen 3"), so this importer can still recover its
# pen number even when Export Tags wasn't run.
PEN_MAT_RE = re.compile(r"^Pen (\d+)$")
# The unique placeholder name pattern written into the tokenized glTF copy
# (see _tokenized_copy below), e.g. "PYTHAN_0", "PYTHAN_1", ...
TOKEN = "PYTHAN_%d"


def _log(*args):
    """Print a diagnostic line (visible in Blender's System Console) when VERBOSE is on."""
    if VERBOSE:
        print("[PYTHA glTF]", *args)


# ── glTF / GLB reading and the temporary renamed copy ───────────────────────

def _read_gltf(path):
    """Return (json_dict, kind, bin_chunk_or_None).

    A .gltf file is plain JSON on disk. A .glb (binary glTF) file is a small
    binary header followed by one JSON "chunk" and usually one binary "BIN"
    chunk holding the raw mesh data; this function tells the two apart by
    the file's first 4 bytes ("glTF" magic = binary) and, for a .glb,
    manually walks its chunk table to pull out the JSON and binary blob.
    """
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
    """Write (json_dict, binary_chunk_or_None) back out as a valid .glb file,
    the inverse of the binary-chunk-walking half of _read_gltf above."""
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
    """Runs one full import: calls Blender's own glTF importer on a
    name-tokenized copy of the file, then rebuilds PYTHA's real group tree,
    names and layer/pen data on top of whatever Blender produced, and
    applies whichever optional clean-up steps the user asked for."""

    def __init__(self, filepath, opts, report=None):
        self.filepath = filepath
        self.o = opts
        self.report = report or (lambda level, msg: None)
        self.parts = []          # (object, node_index)
        self.groups = {}         # node_index -> collection
        self.stats = {}

    def run(self, context):
        # Step 1: read the source file and make the tokenized temp copy, so
        # every object Blender creates can be matched back to a glTF node
        # index regardless of how Blender renames it internally.
        js, kind, binc = _read_gltf(self.filepath)
        nodes = js.get("nodes", [])
        self.nodes = nodes
        gen = js.get("asset", {}).get("generator", "?")
        _log("file:", self.filepath, "| generator:", gen, "| nodes:", len(nodes))
        if not gen.upper().startswith("PYTHA"):
            self.report({"WARNING"}, "Not a PYTHA export (generator '%s') - importing anyway" % gen)

        tmp = _tokenized_copy(self.filepath, js, kind, binc)
        # Snapshot the existing objects first, so after the import we can
        # tell exactly which objects Blender's importer just created (rather
        # than, say, objects already in the scene from something else).
        before = set(bpy.data.objects)
        try:
            bpy.ops.import_scene.gltf(filepath=tmp)
        finally:
            # the tokenized copy is temporary scratch data - always clean it
            # up, even if the import itself raised an error
            try:
                os.remove(tmp)
            except OSError:
                pass
        new_objs = [o for o in bpy.data.objects if o not in before]

        # Match each new Blender object back to its glTF node index via the
        # "PYTHAN_<i>" token prefix written into _tokenized_copy above.
        by_node = {}
        for ob in new_objs:
            m = re.match(r"^PYTHAN_(\d+)", ob.name)
            if m:
                by_node[int(m.group(1))] = ob

        # parents per node (glTF tree), roots from the scene
        # Rebuild the glTF node hierarchy as a plain {child_index: parent_index}
        # map by walking every node's own "children" list - glTF stores the
        # tree top-down (parent lists children), so this just inverts it for
        # convenient parent lookups below.
        parent = {}
        for i, n in enumerate(nodes):
            for c in n.get("children", []):
                parent[c] = i
        scene_roots = js.get("scenes", [{}])[js.get("scene", 0)].get("nodes", [])

        # One root collection per import, named "PYTHA <source file base name>",
        # linked directly into the current scene - everything this import
        # creates lives under this collection.
        base = os.path.splitext(os.path.basename(self.filepath))[0]
        root_col = bpy.data.collections.new("PYTHA " + base)
        context.scene.collection.children.link(root_col)
        self.root_col = root_col

        # collections for group nodes (nodes with children and no mesh, or with children)
        # Lazily creates (and caches in self.groups) a Blender Collection for
        # glTF node `i`, first recursively ensuring its PARENT's collection
        # exists too - so PYTHA's nested group structure (Kitchen > Base >
        # Carcass > ...) comes out as a matching nested collection tree,
        # built top-down the first time any of its descendants needs it.
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
        # Walk every matched (node_index, object) pair in node order and, for
        # each MESH object (skip empties/groups - they're handled purely as
        # collections above): detach it from whatever parenting Blender's
        # importer gave it while preserving its world transform, recover its
        # real PYTHA name and any layer/pen tag from the node's raw name,
        # store that as custom properties, rename the object and its mesh
        # data-block to the clean name, and finally move it out of
        # whichever collection(s) Blender's importer put it in and into the
        # correct PYTHA group collection.
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
        # A part with no real PYTHA material still gets a pen number this
        # way: PYTHA's own glTF export names the fallback material "Pen <n>"
        # for such parts, so for any part that didn't already get
        # "pytha_pen" from an Export Tags tag, check its material slots for
        # a name matching that pattern (stripping Blender's own ".001"-style
        # duplicate suffix first).
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
        # Blender's own glTF importer creates an Empty object for every
        # non-mesh node (its usual way of representing a bare group/joint);
        # since PYTHA groups are now represented as Collections instead
        # (via group_col above), these leftover empties serve no purpose
        # and are deleted.
        empties = [o for o in by_node.values() if o.type == "EMPTY"]
        for e in empties:
            bpy.data.objects.remove(e, do_unlink=True)

        self.stats["parts"] = len(self.parts)
        self.stats["groups"] = len(self.groups)
        self.stats["empties_removed"] = len(empties)
        # Steps 2 onward: the optional extras, each gated behind its own
        # checkbox in the operator's options (self.o).
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
        """Split a raw glTF node name into (clean_name, layer, layer_name, pen).
        If `raw` carries no Export Tags tag (TAG_RE doesn't match), returns
        the name unchanged with layer/pen as None."""
        m = TAG_RE.search(raw)
        if not m:
            return raw, None, None, None
        return raw[:m.start()], int(m.group(1)), m.group(2), int(m.group(3))

    def _layer_and_pen_collections(self):
        """Optional extra: in addition to the group-based collection tree
        already built in run(), also link every part that has layer/pen
        data into a second, parallel "Layers / Layer <n>" (and, if enabled,
        "Pens / Pen <n>") collection tree - the SAME object can belong to
        several collections in Blender, so this doesn't move anything out
        of its group, just adds an alternate way to browse by layer or pen."""
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
            _log("no layer/pen tags found - run 'Export tags' (BCW Export Tags) in PYTHA before exporting to get layers")

    def _swap_materials(self, lib_path):
        """Optional extra: replace every imported material that has a
        same-named counterpart in an external .blend "material library"
        with that library's material (so, e.g., all your "VP-1" laminate
        materials point at one shared, already-configured Blender material
        instead of each import creating its own disconnected copy)."""
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
        # bpy.data.libraries.load's `with` block only DECIDES what to pull in
        # (via the `dst.materials = [...]` assignment); the actual append
        # happens when the block exits, which is why `loaded` below is built
        # from `dst.materials` only after the `with` statement has finished.
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
                # user_remap repoints every user of the old material (every
                # part using it) at `new` in one call, then the now-unused
                # old material is deleted and the library material renamed
                # back to the plain name (since appending may have given it
                # a ".001"-style suffix of its own).
                m.user_remap(new)
                bpy.data.materials.remove(m)
                new.name = old_name
                swapped += 1
        self.stats["materials_swapped"] = swapped
        _log("material library: %d of %d imported materials replaced from %s" % (swapped, len(used), lib_path))

    def _merge_by_distance(self, dist):
        """Optional clean-up: glTF export splits a part into one sub-mesh per
        material, which duplicates every vertex that sits on a material
        seam. This welds back together any vertices within `dist` of each
        other on every imported part, using Blender's bmesh module (loaded
        as a temporary bmesh, not the viewport's live edit-mesh)."""
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
        """Optional clean-up: mark any edge shared by exactly two faces whose
        angle to each other exceeds `angle_limit` (default ~40 degrees) as a
        UV seam - a quick way to get sensible-looking UV island boundaries
        on box-like cabinet parts without manually seaming them."""
        n = 0
        for ob, _ in self.parts:
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            for e in bm.edges:
                if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > angle_limit:
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

    # Each of these becomes one checkbox/field in the file-browser's import
    # options panel (drawn by draw() below); their defaults are what a
    # first-time import gets without changing anything.
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
        """Blender calls this when the user confirms the import dialog.
        Builds a PythaImport with the chosen options, runs it, and reports
        a one-line summary (or the error, if it failed) in Blender's status
        bar / info log."""
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
        """Draws the options panel shown in Blender's file browser sidebar
        while picking a file to import (one row per property above)."""
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
    """Appended to File > Import to add the "PYTHA (.glb/.gltf)" menu entry."""
    self.layout.operator(IMPORT_OT_pytha_gltf.bl_idname, text="PYTHA (.glb/.gltf)")


def register():
    """Standard Blender add-on hook: called when the add-on is enabled."""
    bpy.utils.register_class(IMPORT_OT_pytha_gltf)
    bpy.types.TOPBAR_MT_file_import.append(_menu)


def unregister():
    """Standard Blender add-on hook: called when the add-on is disabled."""
    bpy.types.TOPBAR_MT_file_import.remove(_menu)
    bpy.utils.unregister_class(IMPORT_OT_pytha_gltf)


if __name__ == "__main__":
    register()

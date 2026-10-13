# Pytha Open

A repo for the Pytha projects that I can share, as there is a crushing lack of shared information with this program...

Unofficial community tools, not affiliated with PYTHA Lab. Built and tested on PYTHA V26. Use at your own risk and work on copies.

| Tool | Type | What it does |
|---|---|---|
| [Group Numbering](#group-numbering-v14) | PYTHA Lua plugin | Numbers cabinets left to right |
| [Export Tags](#export-tags-v10) | PYTHA Lua plugin | Keeps layers and pens through a glTF export |
| [PYTHA glTF Importer](#pytha-gltf-importer-v100) | Blender add-on | Imports PYTHA glTF with the group tree, layers and pens |
| [pymat from Textures](#pymat-from-textures) | Python script | Builds `.pymat` material libraries from texture folders |

**Installing the PYTHA plugins:** copy the plugin folder (it contains `config.xml` and `main.lua`) into your PYTHA plugin directory and restart PYTHA. The plugin appears in the plugin sidebar.

---

## Group Numbering v1.4
`Group Numbering v1.4/`

Numbers cabinets (each Cabinet Wizard cabinet, plus every other top-level group): bases first, then uppers, each left to right. The number is written to the group's position number so the Parts List can show it, appended to the group name ("Base" becomes "Base #3"), and optionally placed as an upright 3D label above the group. Existing numbers are kept; only new groups get the next free number.

**How to use**
1. Run **Group Numbering** from the plugin sidebar and choose **Number Groups** (or **Remove number labels**).
2. Set the options: start number, *Renumber everything*, add number to name, 3D labels, label height, layer and pen.
3. Click OK. Re-run after any change; old labels are replaced. Removing labels leaves the numbers and names on the groups.

## Export Tags v1.0
`Pytha to Blender Import/Export Tags v1.0/`

PYTHA's glTF export drops layers and pens. This plugin writes each part's layer and pen into its name as `{L<layer>:<layer name> P<pen>}` so the Blender importer can restore them, then removes the tags again.

**How to use**
1. Run **Tag parts for export**.
2. Export glTF/GLB from PYTHA.
3. Run **Remove export tags** to restore the original part names.

## PYTHA glTF Importer v1.0.0
`Pytha to Blender Import/pytha_gltf_importer.py` (Blender 4.2+ / 5.x)

Imports PYTHA glTF/GLB exports on top of Blender's own importer:
- PYTHA's group tree becomes nested collections instead of 100+ empties.
- Part names are kept exactly (also stored in the `pytha_name` custom property).
- Layers and pens (from Export Tags) become custom properties and `Layers /` and `Pens /` collections.
- Optional material library swap from a `.blend`, merge-by-distance cleanup and hard-edge UV seams.

**How to use**
1. In Blender: *Edit > Preferences > Add-ons > Install from Disk*, pick `pytha_gltf_importer.py`, and enable it.
2. In PYTHA, run **Tag parts for export**, export glTF/GLB, then **Remove export tags**.
3. In Blender: *File > Import > PYTHA (.glb/.gltf)*, set the options (layer/pen collections, material library, merge distance, hard edges) and import.

## pymat from Textures
`Texture Folder to .pymat/pymat_from_textures_shareable.py` (Python 3.8+, `pip install pillow numpy`)

Generates PYTHA `.pymat` material libraries from folders of textures, with colour, roughness/bump wiring and preview thumbnails, which PYTHA's built-in "New from Textures" does not do. Runs as a dry run unless you pass `--write`. Never modifies your textures or the original library.

**How to use**
- **Mode 1, sync an existing library** (adds materials for texture sets it does not link yet; writes `<library>_NEW.pymat`):
  `python pymat_from_textures_shareable.py "C:\path\MY MATERIALS.pymat" --write`
- **Mode 2, one folder to a standalone library** (e.g. a vendor swatch folder):
  `python pymat_from_textures_shareable.py --folder "C:\path\VendorName" --write`
- Useful options: `--strip REGEX` (clean names), `--out FILE`, `--bump auto|rough|height`, `--no-preview`, `--textures DIR`.
- Check the dry-run list first, back up your library, and close PYTHA before swapping a new one in. Keep the `.pymat` and its textures together (links are relative).

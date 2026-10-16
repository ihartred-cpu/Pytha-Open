# Texture Folder to .pymat

Builds PYTHA `.pymat` material libraries from folders of textures, with colour, bump wiring, shine and thumbnails, which PYTHA's built-in "New from Textures" does not do.

It is a single web page, `pymat_from_textures.html`. Double-click it to open in Chrome or Edge. No install, nothing is uploaded, and your textures and original library are never changed.

## How to use
1. Pick a mode:
   - **Add to an existing library**: adds texture sets your `.pymat` doesn't link yet. Writes `<library>_NEW.pymat` next to the original.
   - **New library from a folder**: every image becomes one material (handy for vendor swatch folders). Writes `<folder>.pymat` inside the folder.
2. Click **Choose folder...** (or drag the folder onto the page) and allow the browser to edit it.
3. Review the list: rename materials, untick ones you don't want, and pick the bump map. *Remove from names* strips text such as `540 x 540` from every name.
4. Click **Create .pymat**. Chrome and Edge save into the folder; Firefox and Safari download the file, so move it next to the textures.

## How textures are matched
Each material uses one **colour** map and, optionally, one **bump** map. Images are sorted by the word in the file name, and the word nearest the end wins (`Aluminium_Metal_Sheet_Base_color` is colour, not metal).

| Map | Words | Used for |
|---|---|---|
| Colour | basecolor, albedo, diffuse, color / colour | The texture |
| Bump | bump | Bump slot, 1st choice |
| Height | height, displacement, disp | Bump slot, 2nd choice |
| Roughness | roughness, rough | Bump slot, 3rd choice |
| Normal, AO, metal | normal, nrm, ao, occlusion, metal... | Recognised, then left out |

- **Single-letter endings** (Arroway and others): `_d` colour, `_n` normal, `_b` bump, `_r` roughness, `_h` height. The letter wins over any earlier map word. A trailing `-color2` is ignored when pairing.
- **Sets:** files sharing a name apart from the map word are one material (`oak_basecolor.png` + `oak_roughness.png`). A set needs a colour map. *Bump slot uses* changes the order of the three choices, and you can override it per material.
- **No map word:** *New library from a folder* treats the image as its own swatch and keeps its whole file name. *Add to an existing library* ignores it as a preview. Tick **Use full file names** to name every material after its file.
- **Tile size from names:** with *Read tile size from names* ticked (default), a size with a unit in the name (`100x32cm`; cm, mm, m, in) sets the tile size. The first number is the width. Sizes without a unit (`540 x 540`) are ignored. I haven't confirmed how PYTHA applies the stored size, so check your first material.
- **Shared bump maps (New library from a folder):** vendors often ship one `Bump.jpg` per product. Per folder, a bump/height/roughness image whose name matches a colour image (ignoring `-`, `_`, `.`, spaces) goes with it. Any colour image still without one uses the folder's unpaired bump, so keep each product in its own folder.
- **Rotate all images 90° clockwise** (New library, Chrome or Edge): saves rotated copies of the selected materials' images into a `FolderName (rotated)` folder with the `.pymat`, and links to them. EXIF rotation is applied first. JPEGs stay JPEGs; PNG, TIF and BMP become PNG. Large images are slow and need memory. A `(rotated)` folder is never rescanned as source.

## Bump strength and look
- **Bump strength** sets PYTHA's bump angle for materials with a bump, height or roughness map. Starts at 80, close to PYTHA's own (about 55 to 90). Very low looks flat.
- **Material look** sets the shine of every new material: *Leave as PYTHA default* (writes nothing), *Matte*, *Satin laminate*, *Gloss*, or *Custom* with **Matte**, **Specularity** and **Highlight** sliders. These write the `diffuse`, `reflective` and `gloss-curve` values, worked out from PYTHA's own files. Check one result in the material editor.

## Good to know
- A folder called `textures`, `maps` or `images` is named after the folder above it.
- An unlabelled image beside a real colour map (a preview render) is listed but starts unticked.
- Settings are remembered in this browser; **Reset settings** restores the defaults.
- **Cancel** (or Esc) stops a run between images. Nothing is saved and a half-made `(rotated)` folder is removed.
- New materials get a grey colour, diffuse 0.8, and texture size 0 unless the name gives a size. Set the real size in PYTHA's material editor.
- Back up your library and close PYTHA before swapping a `_NEW` file in. Keep the `.pymat` and its textures together (links are relative).
- The `.pymat` layout was worked out from V26 files and is untested on other versions.

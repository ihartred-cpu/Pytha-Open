# Texture Folder to .pymat

Builds PYTHA `.pymat` material libraries from folders of textures, with colour, bump, shine and thumbnails, which PYTHA's "New from Textures" does not do.

One web page: double-click `pymat_from_textures.html` to open it in Chrome or Edge. No install, nothing uploaded, and your textures and original library are never changed.

## How to use
1. Pick a mode:
   - **Add to an existing library**: adds texture sets your `.pymat` doesn't link yet. Writes `<library>_NEW.pymat` next to the original.
   - **New library from a folder**: every image becomes one material (good for vendor swatch folders). Writes `<folder>.pymat` in the folder.
2. **Choose folder...** (or drag it onto the page) and allow editing.
3. Review the list: rename, untick, pick the bump map. *Remove from names* strips text like `540 x 540`.
4. **Create .pymat**. Chrome and Edge save into the folder; Firefox and Safari download it, so move it next to the textures.

## How textures are matched
Each material has one **colour** map and optionally one **bump** map. The map word nearest the end of the file name wins.

| Map | Words |
|---|---|
| Colour | basecolor, albedo, diffuse, color / colour |
| Bump | bump (1st choice for the bump slot) |
| Height | height, displacement, disp (2nd) |
| Roughness | roughness, rough (3rd) |
| Ignored | normal, nrm, ao, occlusion, metal... |

- Single-letter endings (Arroway): `_d` colour, `_n` normal, `_b` bump, `_r` roughness, `_h` height.
- Files that share a name apart from the map word are one set. A set needs a colour map.
- No map word: *New library* makes it its own swatch; *Add to an existing library* treats it as a preview and skips it.
- **Use full file names** names every material after its file.
- **Tile size from names** (default on): a size with a unit (`100x32cm`) sets the tile size, width first. Sizes with no unit are ignored. Check your first material, as I haven't confirmed how PYTHA applies it.
- **Shared bump maps** (New library): a bump/height/roughness image whose name matches a colour image is paired with it, ignoring `-`, `_`, `.` and spaces. A colour image with no match uses the folder's unpaired bump, so keep each product in its own folder.
- **Rotate all images 90°** (New library, Chrome or Edge): saves rotated copies into a `FolderName (rotated)` folder and links to them. JPEGs stay JPEGs; PNG, TIF and BMP become PNG. Large images are slow.

## Bump and shine
- **Bump strength** is PYTHA's bump angle (default 80; PYTHA's own are about 55 to 90).
- **Material look** sets shine for every new material: PYTHA default, Matte, Satin laminate, Gloss, or Custom sliders. Check one result in the material editor.

## Good to know
- A folder named `textures`, `maps` or `images` takes the name of the folder above it.
- Unlabelled preview renders are listed but start unticked.
- Settings are remembered in the browser; **Reset settings** clears them. **Cancel** or Esc stops between images and saves nothing.
- New materials start grey, diffuse 0.8, tile size 0 unless the name gives a size. Set the real size in PYTHA.
- Back up your library and close PYTHA before swapping in a `_NEW` file. Keep the `.pymat` and its textures together.
- Layout worked out from V26 files; untested on other versions.

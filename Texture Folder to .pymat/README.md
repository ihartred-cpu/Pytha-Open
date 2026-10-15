# Texture Folder to .pymat

Builds PYTHA `.pymat` material libraries from folders of textures, with colour, roughness/bump wiring and preview thumbnails, which PYTHA's built-in "New from Textures" does not do.

It is a single web page, `pymat_from_textures.html`. Double-click it to open in Chrome or Edge. No install, and nothing is uploaded; it runs entirely in your browser. It never changes your textures or your original library.

## How to use
1. Pick a mode:
   - **Add to an existing library**: finds texture sets your `.pymat` doesn't link yet and adds them. Writes `<library>_NEW.pymat` next to the original.
   - **New library from a folder**: every image becomes one material (handy for vendor swatch folders). Writes `<folder>.pymat` inside the folder.
2. Click **Choose folder...** (or drag the folder onto the page) and allow the browser to edit the folder.
3. Review the list: rename materials, untick ones you don't want, and pick which map feeds the bump slot. *Remove from names* strips text such as `540 x 540` from every name.
4. Click **Create .pymat**. Chrome and Edge save straight into the folder; Firefox and Safari download the file instead, so move it next to the textures.

## How textures are matched
A PYTHA material made by this page uses two images: a **colour** map (the texture) and, optionally, one **bump** map.

The page sorts images by the word in their file name:

| Map | Words it looks for | Used for |
|---|---|---|
| Colour | basecolor, albedo, diffuse, color / colour | The material's texture |
| Bump | bump | Bump slot (1st choice) |
| Height | height, displacement, disp | Bump slot (2nd choice) |
| Roughness | roughness, rough | Bump slot (3rd choice) |
| Normal, AO, metal | normal, nrm, ao, occlusion, metal... | Recognised so they are not mistaken for colour, then left out |

Some vendors (Arroway, for one) end the file name with a single letter instead: `_d` colour, `_n` normal, `_b` bump, `_r` roughness, `_h` height. These are recognised too, and the letter wins over any map word earlier in the name, so a finish called "rough" is not mistaken for a roughness map. A trailing `-color2` on the colour file is ignored when pairing it with its other maps.

Images in the same folder that share a name apart from that word are one set: `oak_basecolor.png` and `oak_roughness.png` become one material. A set needs a colour map to become a material. The *Bump slot uses* option changes the order of the three bump choices, and you can pick a different map (or none) per material in the list.

**Tile size from names.** Vendor names often carry the real size of the image, such as `100x32cm`. With *Read tile size from names* ticked (the default), a name with a size and a unit (cm, mm, m or in) sets the material's tile size, so the texture repeats at true scale instead of leaving PYTHA's default. Sizes without a unit, such as `540 x 540`, are ignored. The first number is the image's width and the second its height; if *Rotate all images* is on, the two are swapped. Check the first material you make in PYTHA, because I have not been able to confirm how PYTHA applies the stored size.

**Which word is the map type.** The map word nearest the end of the name wins, so `Aluminium_Metal_Sheet_Base_color` is a colour map, not a metalness map.

Images with no map word in their name are handled by mode: *New library from a folder* treats each one as its own colour map (a vendor swatch), while *Add to an existing library* ignores them as previews or strays.

In *New library from a folder* mode, an image with no partner maps is treated as a swatch and keeps its whole file name, so `1234 Some Colour.jpg` stays "1234 Some Colour". Tick **Use full file names** to name every material exactly after its image file.

**Shared bump maps (New library from a folder).** Vendors often ship one `Bump.jpg` per product that every finish uses, so the names never match. In this mode the page pairs maps like this, folder by folder:

1. A bump, height or roughness image whose name matches a colour image (ignoring `-`, `_`, `.` and spaces) goes with that image, e.g. `alter-lm98.jpg` and `alter-lm98_Height.jpg`.
2. Any colour image still without one uses the folder's unpaired bump (or height, or roughness) image. Put each product in its own folder so every finish shares that product's bump.

You can still change or clear the bump for any material in the list. *Add to an existing library* mode does not share bumps.

**Rotate all images 90° clockwise (New library from a folder, Chrome or Edge).** Tick this to turn every texture a quarter turn, for example to make portrait sheets landscape. The page saves rotated copies of the images used by the selected materials into a new `FolderName (rotated)` folder inside the folder you chose, with the `.pymat` next to them, and links the materials to the copies. Your originals are not changed. Any EXIF rotation in a photo is applied first. JPEGs stay JPEGs; PNG, TIF and BMP images are saved as PNG. Rotating very large images takes a while and needs plenty of memory, and a `(rotated)` folder is never scanned as source textures if you pick the folder again.

## Bump strength
**Bump strength** sets PYTHA's bump angle for every material that has a bump, height or roughness map. It starts at 80, close to PYTHA's own materials (about 55 to 90). Very low values look flat. It is remembered with your other settings.

## Material look (shine)
The **Material look** menu sets how shiny every new material is in PYTHA:
- **Leave as PYTHA default** writes nothing, as before.
- **Matte**, **Satin laminate** and **Gloss** are ready-made starting points.
- **Custom** shows three sliders: **Matte**, **Specularity** and **Highlight** (the strength of the Specular Highlight curve).

It applies to every material in the run and is remembered with your other settings. These map to the `diffuse`, `reflective` and `gloss-curve` values in the `.pymat` (worked out from PYTHA's own material files). Check one result in PYTHA's material editor the first time.

## Good to know
- A folder called `textures` (or `maps`, `images`, ...) is named after the folder above it.
- An unlabelled image next to a real colour map (a preview render such as `Metal009.png`) is listed but starts unticked.
- Your settings (bump slot, name cleanup, full file names, rotate, tile size, thumbnails) are remembered in this browser for next time. **Reset settings** puts them back to the starting values.
- **Cancel** (or press Esc) stops a run in progress. It takes effect between images, so a very large image finishes first. Nothing is saved, and a half-made `(rotated)` folder is removed again. Your originals are never touched.
- Back up your library and close PYTHA before swapping a `_NEW` file in.
- Links are relative: keep the `.pymat` and its textures together.
- New materials get a grey colour, diffuse 0.8 and texture size 0. Set the real texture size in PYTHA's material editor.
- The `.pymat` layout was worked out from V26 files; it is untested on other versions.

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

## Good to know
- Back up your library and close PYTHA before swapping a `_NEW` file in.
- Links are relative: keep the `.pymat` and its textures together.
- In *Add to an existing library* mode, images need a map word in their name (colour, basecolor, diffuse, albedo, roughness, bump, height...) to be picked up. Others are treated as previews and ignored.
- New materials get a grey colour, diffuse 0.8 and texture size 0. Set the real texture size in PYTHA's material editor.
- The `.pymat` layout was worked out from V26 files; it is untested on other versions.

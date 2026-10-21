# Pytha Open

A repo for the Pytha projects that I can share, as there is a crushing lack of shared information with this program...

Unofficial community tools, not affiliated with PYTHA Lab. Built and tested on PYTHA V26. Use at your own risk and work on copies.

| Tool | Type | What it does |
|---|---|---|
| [Group Numbering](Group%20Numbering%20v1.7/) | PYTHA plugin | Numbers top-level groups (and Kitchen Wizard cabinets) left to right |
| [Sheet Kit (beta)](Sheet%20Kit%20v0.5%20beta/) | PYTHA plugin | Makes a plot sheet with front, top and side views of the model, view labels, a title block and US architectural scales |
| [Glyph Lab](Glyph%20Lab%20v0.6/) | PYTHA plugin (test) | Builds a smiley and a warning sign several ways (text, linework, extruded faces, booleans) and reports which Lua calls your install accepts |
| [Profile Runs](Profile%20Runs%20v0.1/) | PYTHA plugin | LED channel runs and closet rods, named so Workshop rules can cut the grooves and holes (untested in PYTHA so far) |
| [Playground](Playground%20v0.1/) | PYTHA plugin | Small games (Road Racer, Sheet Tetris) that double as practice for the Lua timer and dialog API (both tested in PYTHA V26) |
| [Pytha to Blender Import](Pytha%20to%20Blender%20Import/) | PYTHA plugin + Blender add-on | Brings PYTHA glTF exports into Blender with the group tree, layers and pens |
| [Texture Folder to .pymat](Texture%20Folder%20to%20.pymat/) | Web page | Builds `.pymat` material libraries from texture folders |

Each folder has its own README with setup and usage.

**Installing PYTHA plugins:** each plugin lives in its own folder inside PYTHA's plugin directory, `%AppData%\Roaming\PYTHA26.0\plugins`. Copy the whole plugin folder (the one containing `config.xml` and `main.lua`) there, keeping the folder itself, and restart PYTHA. The plugin appears in the plugin sidebar.

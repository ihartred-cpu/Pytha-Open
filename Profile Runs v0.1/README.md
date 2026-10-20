# Profile Runs 0.1

Straight runs of a fixed cross-section, named so the shop's own Workshop / Type Automatic rules can cut the grooves and holes. **The plugin cuts nothing itself.**

| Type | Parts made | Settings |
|---|---|---|
| LED channel | channel body named `LED Channel,<profile>`, `LED Diffuser`, `LED Strip` | run length, profile (surface 17x7, recessed 17x7, recessed slim 10x5, corner 45deg 16x16), run along X or Y, light direction (down / up / front-left / back-right), diffuser and strip on or off |
| Closet rod | `Closet Rod`, `Rod socket L/R`, `Rod support N` | opening width, round or oval (defaults 1-5/16 in round, 1-5/8 x 15/16 in oval), end sockets, centre support every N and its height |

- **Naming drives the machining.** The body name comes from the "Part name" field (`%s` = the profile label), so a groove rule can key on `LED Channel,Recessed 17x7`. Diffuser and strip have separate names so they never fire the rule.
- **Origin.** LED channel: start of the run, centre of the mounting face (recessed profiles sit behind that face, so they go into the panel). Closet rod: left face of the opening, rod centre.
- **Profile sizes are generic guesses** (mm, in the `PROFILES` table at the top of `main.lua`). Replace them with the shop's real channel: each entry is a closed outline plus diffuser and strip rectangles, in a (u across, v toward the light) frame.
- **Editing later:** menu entry "Profile Runs - Edit selected" (a plain function extension; settings are stored on the group).

Install: copy this folder to `%AppData%\Roaming\PYTHA26.0\plugins\`, restart PYTHA, run "Profile Runs".

## Status
Written 2026-10-18; run only against a mock of the PYTHA API (part counts, extents and names checked for every profile, direction and axis). **Not yet run in PYTHA.**
First-run checks: extrusion direction and start point, the recessed body landing behind the mounting face, light direction labels, round and oval rod outlines (the oval is a 40-sided polygon), preview speed.

## Not in 0.1
- Runs along an arbitrary path with mitred corners (`pytha.create_sweep` along a picked polyline). The wiki does not say how a custom cross-section is placed relative to the path, so this needs a hands-on test first.
- Real channel profiles and a profile library file.

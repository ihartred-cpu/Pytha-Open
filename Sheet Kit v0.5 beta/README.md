# Sheet Kit (beta) 0.5

Makes a new plot sheet from your model: front, top and side views of all top-level groups, a label under each view, a title block (title, sheet number, scale, date) and a US architectural scale.

**Beta.** Built and tested on PYTHA V26 (compiled 2026-07-20 14:19:45) in an inch document (Letter landscape for 0.2; 0.3 adds an Arch D 36 x 24 preset), using only calls that run on V26: `pyplot.create_sheet`, `pyplot.insert_detail`, `pyplot.insert_text`. It has been run on two real cabinet models and drew the three views the right way round (third-angle: top above front, right side view to the right of front). Expect rough edges.

## Use

1. Install: copy this folder to `%AppData%\Roaming\PYTHA26.0\plugins\` (keep the folder itself, with `config.xml` and `main.lua` inside) and restart PYTHA.
2. Run "Sheet Kit (beta)" with your cabinets in top-level groups.
3. Fill in the sheet name, title and sheet number. Sheet size: `archd` (36 x 24, default) or `letter`. Scale: leave blank for auto, or type inches per foot (`1/8`, `1/4`, `1/2`, `3/4`, `1`, `1-1/2`, `3`, `6`).
4. To draw only one cabinet or group, tick "Only draw groups I click in the model", press OK, then click the cabinet(s) in the model and confirm. Clicking picks parts, so a neighbour can slip in: after you confirm the pick, the groups found are highlighted and listed (name and size) for you to accept or cancel. Only those groups are drawn, and the scale and layout are worked out from them. Several groups share one sheet unless you also tick "one sheet per picked group". "Levels up" chooses how far to climb from the clicked part: 0 is the group directly around it, 1 its parent group, and so on. This uses `pyux.select_part`, which worked on V26 (seen).
5. "Set the real view scale" (on by default) passes the scale to PYTHA. Untick it to fall back to the 0.2 method (views sized to fit, no scale set).

Scales offered: 1/8", 3/16", 1/4", 3/8", 1/2", 3/4", 1", 1-1/2", 3", 6", full size. Auto picks the largest that fits. If a typed scale does not fit you get a warning and the views will overlap or run past the frame. With the real scale on, the views are placed with `insert_detail`'s `scale` (see notes), which was worked out on one test model: check one dimension on your first sheet.

## Known limits

- **No dimensions.** The Lua dimension calls live in the `pydim` namespace, which does not exist on V26 (the wiki lists it for V27). Add dimensions by hand on the sheet.
- Layout presets are **Letter landscape** and **Arch D landscape (36 x 24)** in an **inch** document. Other sheet sizes and millimetre documents are untested. The title block is still a simple text line, not a real title strip.
- It draws **all top-level groups** (skipping groups named "Group Numbers" and "Glyph Lab"). Loose parts outside a group are not scanned.
- `create_sheet` uses the default plot sheet template, so the border and any template text come from that.
- The title block is plain text placed on the sheet, not PYTHA header fields.

## Notes for plugin authors (seen on V26)

- `insert_detail` with `view_min`/`view_max` and no `scale` places and fits the view into `size`. `position` is the view's centre, in document units.
- With `scale` = N (a **denominator**: 1/8" = 1' is 96, 1/4" = 1' is 48, 1" = 1' is 12) the view is drawn at 1:N, the view's origin (model 0,0 on its two axes) lands on `position`, and `size` is a crop frame centred on `position`. `view_min`/`view_max` made no difference. No `scale` and no clip draws at the sheet's default scale (the "M 1:5" in the status bar). Seen on one model whose box started at 0,0,0.
- `insert_text` `position` is the text's top-left (it hangs down from y), in document units; `size` is in mm. `orientation` is alignment; rotation is `angle` (degrees, not tested here).
- The reusable part is the `SheetKit` block at the top of `main.lua` (`place_view`, `text`, `model_bounds`, `elevations_sheet`); copy it into your own plugin.

Feedback and reports from other PYTHA versions are welcome.

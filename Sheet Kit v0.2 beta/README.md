# Sheet Kit (beta) 0.2

Makes a new plot sheet from your model: front, top and side views of all top-level groups, a label under each view, a title block (title, sheet number, scale, date) and a US architectural scale.

**Beta.** Built and tested on PYTHA V26 (compiled 2026-07-20 14:19:45) in an inch document on a Letter landscape sheet, using only calls that run on V26: `pyplot.create_sheet`, `pyplot.insert_detail`, `pyplot.insert_text`. It has been run on two real cabinet models and drew the three views the right way round (third-angle: top above front, right side view to the right of front). Expect rough edges.

## Use

1. Install: copy this folder to `%AppData%\Roaming\PYTHA26.0\plugins\` (keep the folder itself, with `config.xml` and `main.lua` inside) and restart PYTHA.
2. Run "Sheet Kit (beta)" with your cabinets in top-level groups.
3. Fill in the sheet name, title and sheet number. Scale: leave blank for auto, or type inches per foot (`1/2`, `3/4`, `1`, `1-1/2`, `3`, `6`).

Scales offered: 1/2" = 1'-0" (smallest), 3/4", 1", 1-1/2", 3", 6", full size. Auto picks the largest that fits. If a typed scale does not fit you get a warning and the views will overlap or run past the frame. The scale is worked out from the model size and used to size the views; PYTHA does not report it back, so check one dimension on the first sheet.

## Known limits

- **No dimensions.** The Lua dimension calls live in the `pydim` namespace, which does not exist on V26 (the wiki lists it for V27). Add dimensions by hand on the sheet.
- Layout constants assume **Letter landscape (11 x 8.5 in)** in an **inch** document. Other sheet sizes and millimetre documents are untested.
- It draws **all top-level groups** (skipping groups named "Group Numbers" and "Glyph Lab"). Loose parts outside a group are not scanned.
- `create_sheet` uses the default plot sheet template, so the border and any template text come from that.
- The title block is plain text placed on the sheet, not PYTHA header fields.

## Notes for plugin authors (seen on V26)

- `insert_detail` with `view_min`/`view_max` and no `scale` places and fits the view into `size`. `position` is the view's centre, in document units.
- `insert_text` `position` is the text's top-left (it hangs down from y), in document units; `size` is in mm. `orientation` is alignment; rotation is `angle` (degrees, not tested here).
- The reusable part is the `SheetKit` block at the top of `main.lua` (`place_view`, `text`, `model_bounds`, `elevations_sheet`); copy it into your own plugin.

Feedback and reports from other PYTHA versions are welcome.

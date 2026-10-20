# Plan Callouts 0.1

Makes a NEW plot sheet with a plan (top) view of the model, a number and a short code on every cabinet, and a cabinet schedule beside it. It reads the cabinet data Kitchen Wizard stores on each cabinet, the number written by [Group Numbering](../Group%20Numbering%20v1.7/) (run that first), and any hardware tags you add.

## What it shows
- **On the plan:** the number (bold) and a code, e.g. `4 / DWR STACK 3`, `6 / TALL`, `3 / TRASH RO`. Codes wrap or shrink to the cabinet width; a cabinet too narrow gets the number only. **Uppers** sit over the bases in plan, so their label goes just behind the cabinet (the wall side) with the number in brackets, `(7)`.
- **Schedule (right of the plan):** per run (left wall, back wall, ...), bases/talls first and uppers after: a summary line such as `BACK WALL: SINK - DW - TRASH RO - DWR STACK 3 - UC REFER - TALL`, then one line per cabinet with number, code, sink model if readable, and width.

## Codes
Edit the tables at the top of `main.lua`.
- Base cabinets by front style: drawers = `DWR STACK n`, doors = `BASE`, door + drawer = `DOOR+DWR`, open = `OPEN`, split styles.
- Kitchen Wizard types: sink = `SINK`, dishwasher = `DW`, fridge (base row) = `UC REFER`, high = `TALL`, high_appliance1 = `TALL OVEN`, high_fridge = `TALL REFER`, hob = `COOKTOP`, wall = `WALL`, corner / blind end / filler / diagonal / hood and so on. An unknown type shows its name in capitals.
- **Sink spec:** the sink model name is added to the schedule line (`SINK - Steel_Sink_01`) if the handle the wizard stored can still give its name. Untested: the name may simply be missing.
- **Groups that are not Kitchen Wizard cabinets** show their group name in capitals.

## Hardware tags (trash RO, LeMans, UC wine, ...)
Run **Plan Callouts - Tag hardware**, click the cabinet(s), confirm, pick an action (add, replace, clear) and a tag from the list or type your own. A tag replaces a generic code (`BASE`, `OPEN`) so a plain base tagged TRASH RO reads `TRASH RO`; on any other code it is added (`DWR STACK 3 + LEMANS`). Tags are stored on the cabinet group. Running Kitchen Wizard Edit rebuilds the kitchen and clears them, as it clears the numbers: tag after the last Edit. Edit the `HARDWARE` list at the top of `main.lua` for the shop's own names.

## Use
1. Run Group Numbering. 2. Run Plan Callouts, set sheet name, title, number, paper (`archd` or `letter`) and scale (blank = auto). 3. Tick **Preview only** first to see the schedule text and which cabinets lack a number without making a sheet.

Install: copy this folder to `%AppData%\Roaming\PYTHA26.0\plugins\`, restart PYTHA.

## Status
Written 2026-10-18; run only against a mock of the PYTHA API (kitchen with sink, DW, tagged trash, 3-drawer stack, UC refer, tall, two uppers: codes, wrapping, schedule and positions checked). **Not yet run in PYTHA.** Check on the first sheet: that the callouts land on their cabinets (the position maths follows Sheet Kit's scaled-view notes, which were worked out on one model), text size, the uppers' labels, the schedule fitting the frame, and that the sink model name appears.
Known limits: text stays horizontal on side and front runs; no leader lines; no dimensions (needs V27).

## Plan Callouts - Elevations (added v0.1)

Second entry in the same plugin. Makes a sheet with a front elevation per run: a number under every cabinet (same numbers as the plan, uppers in brackets on their own row), and text **only** for spec'd items (sink + model name if readable, DW, fridge, range/hob, hood, tall appliances) and tagged hardware (trash RO, LeMans, UC wine...). Plain cabinets (drawer stacks, talls, bases) get a number only.

- Runs facing the back wall use the front view (xz); runs facing the left wall use the right view (yz). Right-wall and front-wall runs are listed as "not drawn" because the sheet views only look from the front and right.
- Tags come from the same `Tag hardware` function as the plan callouts.
- Settings remembered under `plan_elevations_settings`.
- Untested in Pytha (mock only): check view alignment of the label row against the cabinets, and whether the sink model name reads back.

## Plan Callouts - Sections (added v0.1)

Fourth and fifth menu entries: **Sections** and **Remove sections**.

- Sections makes a sheet with side cuts and/or elevation cuts (the 'Cuts' box: side, elevation or both; default both). Side = perpendicular to the run, elevation = parallel to the run through mid-depth, which shows drawer boxes, shelves and dividers from the front. Sections are named `CAB n S` and `CAB n E`. Each cut (hatched) through every spec'd or hardware-tagged cabinet (tick "every cabinet" for all), laid out in a grid at one scale (auto, or typed inches per foot), each labelled `SECTION n` with its spec/hardware text. Cuts are through the cabinet's centre, perpendicular to its run, scoped to that cabinet group only.
- Each section is a real Pytha section object named `CAB n`, so its **cut line and label draw on every plan and elevation sheet** (the V26 behaviour seen in View Lab). The sections stay in the model; **Remove sections** deletes the ones made in this session (handles are not kept across restarts, so older ones need deleting by hand).
- Untested in Pytha (mock only): whether `insert_section` with an explicit scale places the cut at the centre position, hatching appearance, and whether a section scoped to one group also shows neighbouring cabinets.

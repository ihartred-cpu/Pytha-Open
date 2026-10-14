# Group Numbering v1.4

PYTHA plugin (V26). Numbers every top-level group in the model, left to right, so each one carries a number through to the Parts List.

- **Any top-level group** counts as one item, whatever made it.
- **Kitchen Wizard kitchens** are the exception: each cabinet inside the kitchen gets its own number, not the kitchen as a whole (its Benchtop and Kickboard groups are skipped).
- **Order:** bases first (Kitchen Wizard base and tall cabinets, plus every other top-level group), then uppers (Kitchen Wizard wall cabinets), each left to right.

What each number does:
- It is written to the group's position number, so the Parts List can show it.
- It is appended to the group name ("Base" becomes "Base #3").
- Optionally, it is placed as an upright 3D label above the group.

Existing numbers are kept; only new groups get the next free number. *Renumber everything* restarts the sequence.

## Install
Copy this folder (`config.xml` + `main.lua`) into your PYTHA plugin directory and restart PYTHA.

## How to use
1. Run **Group Numbering** from the plugin sidebar and choose **Number Groups** (or **Remove number labels**).
2. Set the options: start number, *Renumber everything*, add number to name, 3D labels, label height, layer and pen.
3. Click OK. Re-run after any change; old labels are replaced. Removing labels leaves the numbers and names on the groups.

Note: running Kitchen Wizard *Edit* rebuilds the kitchen, so its cabinets lose their numbers and get new ones on the next run.

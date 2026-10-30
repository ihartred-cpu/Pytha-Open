-- Group Numbering v1.7 (2026-10-20 addition) - overlap check: a warning (in the summary and the preview) when two cabinets overlap by 30% or more of the smaller one, e.g. a second run started on top of an existing one. Nothing is moved or deleted.
-- Group Numbering v1.6 (2026-10-16) - centres and labels now come from the box of the group's PARTS, not the group's own bounding box.
--   On V26 a group's bounding box also covers its reference points (connection, hinge and handle points), which stretched the box of
--   cabinets that carry them, moved their centre and put numbers out of order and labels off the cabinet. New dialog option "Use the
--   parts' own box (ignore reference points)", on by default; untick it for the 1.6 behaviour. The preview shows where reference
--   points shifted a centre. A reference point sitting on a PART still counts: parts' boxes include theirs.
--   Also: a label whose later steps fail is deleted instead of left in the model; error text no longer gets a second location prefix;
--   menu and description texts no longer say plain "left to right" (the order follows each cabinet's facing).
--   The group name is read back after it is set; if PYTHA ignored set_element_name the name attribute (3) is written directly,
--   and the summary reports names that still did not stick.
--   Variable names were made readable (settings, entry, box, part_box, centre_x ...); behaviour is unchanged.
-- Group Numbering v1.6 (2026-10-16) - centres and labels now come from the box of the group's PARTS, not the group's own bounding box.
--   On V26 a group's bounding box also covers its reference points (connection points, hinge and handle points), which stretched the
--   box of cabinets that carry them, moved their centre and put numbers out of order and labels off the cabinet. New dialog option
--   "Use the parts' own box (ignore reference points)", on by default; untick it to get the 1.5 behaviour. The preview now shows when
--   reference points shifted a centre. A reference point sitting on a PART still counts: parts' boxes include theirs.
-- Group Numbering v1.5 (2026-10-15) - numbers follow each cabinet's FACING instead of always running along the x axis: the order is
--   walked clockwise round the room (left wall, back wall, right wall, front wall), and inside a run it goes left to right as seen
--   from the front of the cabinets. 3D labels sit on the front face and face the same way. The facing comes from pytha.get_group_angle
--   (V26: the group's rotation about its own vertical axis, degrees; 0 = facing -y is ASSUMED, check with "Preview the order" first).
--   New dialog options: order by facing (default on), flip the angle sign, preview only. Old x-axis order = untick "order by facing".
-- Group Numbering v1.4 (2026-10-13) - ONE menu entry "Group Numbering" opens a picker (Number Groups / Remove number labels); PYTHA's
--   plugin sidebar shows at most 21 entries in total, so each Group plugin now has a single entry. number_groups / remove_labels unchanged.
-- Group Numbering v1.3 (2026-10-09) - label pen (colour) in the dialog; parts without a material show in their pen colour
-- Group Numbering v1.2 (2026-10-08) - menu entry renamed "Number Groups"
-- Group Numbering v1.1 (2026-10-08)
-- Numbers cabinets and writes the number to the group's position number (attribute 46), so the Parts List
-- can show it and every part inside carries it (attribute 122). The number is also added to the group's
-- name ("Base" -> "Base #3") and, optionally, shown as an upright 3D label above the group.
--
-- What is a "cabinet" (decision 1, changed in 1.1):
--   * inside a Kitchen Wizard kitchen (a top-level group carrying the wizard's element history), every
--     cabinet group of the kitchen - not the kitchen as a whole, not its Benchtop / Kickboard groups;
--   * any other top-level group counts as one item.
-- Order (decision 2): all bases (wizard base and high cabinets + every other top-level group) left to right,
-- then all uppers (wizard wall cabinets) left to right.
-- Existing numbers are kept (decision 6, changed in 1.1, Cabinet Vision style "every new assembly gets a new
-- number"): only groups without a number - or a copy carrying a number already used further left - get the
-- next free numbers. "Renumber everything" in the dialog restarts the whole sequence.
-- All design choices, with dates and alternatives: DOCUMENTATION/PLUGINS/Group_Numbering_README.md.
--
-- V26 facts this relies on (confirmed by Group Test Suite 1.2-1.4, 2026-10-08):
--   enumerate_groups is an iterator and also returns nested groups -> keep parent == nil;
--   attribute 46 is writable on groups; parts inherit it as attribute 122;
--   create_text_3d takes (text, height, thickness) only - place it with push_local_coordinates.

-- ────────────────────────────────────────────────────────────────────────────
-- CONSTANTS - the plugin's tunable knobs, gathered in one place so you don't
-- have to go hunting through the functions below to change a default.
-- ────────────────────────────────────────────────────────────────────────────

local LABEL_GROUP_NAME = "Group Numbers"		--all labels live in this one top-level group, never inside the numbered groups
local LABEL_PREFIX = "Group No. "
local NAME_SEPARATOR = " #"					--"Base" -> "Base #3"
local WIZARD_HISTORY_KEYS = {"wizard_history"}	--Kitchen Wizard's element-history key
local WALL_ROW = 0x2						--Kitchen Wizard row code for wall cabinets
local OVERLAP_MIN_RATIO = 0.3			--two cabinets count as overlapping when they share this much of the SMALLER one's box (touching faces and thin overlaps do not)
local OVERLAP_TOL_MM = 2				--an overlap thinner than this on any axis is just two cabinets touching

-- The dialog's starting values, and what gets written to disk between runs
-- (see load_settings below). Changing a value here only changes what a
-- brand-new install starts with; existing users keep whatever they last set
-- in the dialog, because load_settings loads their saved choices on top of
-- these.
local DEFAULTS = {
	start = 1,
	renumber_all = false,
	rename = true,
	labels = true,
	label_height_mm = 76.2,		--3in
	label_gap_mm = 50,			--above the top of the group
	layer = 0,					--0 = active layer
	pen = 0,					--0 = leave PYTHA's current pen; pick a red pen in the dialog to get red numbers
	facing = true,				--order and label by each group's facing (get_group_angle); false = the old left-to-right along x
	flip_angle = false,			--if the preview shows the angles running the other way round, tick this
	preview = false,			--list the order and the angles, change nothing
	geometry_box = true,		--centres and labels from the box of the group's parts; false = the group's own box (includes reference points)
}

-- ────────────────────────────────────────────────────────────────────────────
-- UNITS - PYTHA's own API always works in the document's current length unit
-- (mm or inch, whichever the user has the document set to). This plugin
-- stores its own settings internally in millimetres so the numbers in
-- numbering_settings.* never change meaning if the user later switches the
-- document's unit; these two helpers convert at the boundary, right where a
-- value is about to be shown in or read from the dialog.
-- ────────────────────────────────────────────────────────────────────────────

--millimetres (how this plugin stores lengths) -> the document's current unit (for display/dialog use)
local function to_doc(v_mm)
	if pytha.get_length_unit() == "in" then
		return v_mm / 25.4
	end
	return v_mm
end

--the document's current unit -> millimetres (for storing)
local function to_mm(v_doc)
	if pytha.get_length_unit() == "in" then
		return v_doc * 25.4
	end
	return v_doc
end

-- Load this plugin's remembered settings (pyio.load_values is PYTHA's small
-- per-plugin key/value store, saved between sessions). We start from a FRESH
-- copy of DEFAULTS and only overwrite a key if the saved value exists AND is
-- the same Lua type as the default - that way an older save file missing a
-- newer option (like "facing", added in 1.5) just falls back to the default
-- for that one option instead of breaking the whole settings table.
local function load_settings()
	local settings = {}
	for key, value in pairs(DEFAULTS) do
		settings[key] = value
	end
	local saved = pyio.load_values("numbering_settings")
	if type(saved) == "table" then
		for key, value in pairs(saved) do
			if DEFAULTS[key] ~= nil and type(value) == type(DEFAULTS[key]) then
				settings[key] = value
			end
		end
	end
	settings.renumber_all = false		--never remembered: a full renumber must be asked for each time
	settings.preview = false			--never remembered either
	settings.pen_choice = nil
	return settings
end

-- Read a group's name (PYTHA attribute 3). Wrapped in pcall because some
-- element kinds can raise an error when you ask for this attribute; if that
-- happens we just treat the group as having no name ("") rather than letting
-- the error propagate and abort the whole run.
local function group_name(group)
	local call_ok, name_value = pcall(function() return pytha.get_element_attribute(group, 3) end)
	if call_ok and name_value ~= nil then
		return tostring(name_value)
	end
	return ""
end

local function base_name(name)
	--strip a number added by an earlier run ("Base #3" -> "Base")
	return (name:gsub(" #%d+$", ""))
end

-- Read back a number this plugin may have written to a group on an earlier
-- run (PYTHA attribute 46, the group's "position number", also shown in the
-- Parts List). Used so re-running the plugin doesn't renumber everything
-- from scratch - see the "keep existing numbers" logic in number_groups().
local function existing_number(group)
	local call_ok, raw_number = pcall(function() return pytha.get_element_attribute(group, 46) end)
	if not call_ok or raw_number == nil then
		return nil
	end
	local number = tonumber(raw_number)
	if number ~= nil and number >= 1 and number == math.floor(number) then
		return math.floor(number)		--integer: PYTHA hands attributes back as text, e.g. "40.0" -> 40, never "Base #40.0"
	end
	return nil
end

-- Find the top-level group(s) named "Group Numbers" that hold this plugin's
-- own 3D number labels from a previous run (there should normally be at most
-- one, but we handle more just in case a user merged files or ran an older
-- version that behaved differently).
local function find_label_groups()
	local found = {}
	for group in pytha.enumerate_groups() do
		if pytha.get_element_parent_group(group) == nil and group_name(group) == LABEL_GROUP_NAME then
			table.insert(found, group)
		end
	end
	return found
end

-- Delete every "Group Numbers" label group found above, and report how many
-- were removed. Called both by "Remove number labels" and at the start of
-- "Number Groups" (so re-running always replaces old labels instead of
-- stacking new ones on top).
local function delete_labels()
	local old = find_label_groups()
	if #old > 0 then
		pytha.delete_element(old)
	end
	return #old
end

-- If `group` is a Kitchen Wizard kitchen, return its own element-history data
-- (an internal PYTHA table the wizard attaches to the kitchen group, holding
-- aux_values.cabinet_list - the list of cabinets the wizard generated). For
-- any ordinary group (not a wizard kitchen) this returns nil, which is how
-- collect() below tells "one wizard kitchen full of cabinets" apart from
-- "one plain top-level group that counts as a single item".
local function wizard_data(group)
	for _, key in ipairs(WIZARD_HISTORY_KEYS) do
		local call_ok, data = pcall(function() return pytha.get_element_history(group, key) end)
		if call_ok and type(data) == "table" and type(data.aux_values) == "table" and type(data.aux_values.cabinet_list) == "table" then
			return data
		end
	end
	return nil
end

-- The group's own PYTHA bounding box: {{min_x,min_y,min_z}, {max_x,max_y,max_z}}.
-- NOTE: on V26 this box also stretches to cover the group's reference points
-- (connection/hinge/handle points), which is exactly the problem parts_box()
-- below works around.
local function bounding_box(group)
	local call_ok, box = pcall(function() return pytha.get_element_bounding_box(group) end)
	if call_ok and type(box) == "table" and box[1] ~= nil and box[2] ~= nil then
		return box
	end
	return nil
end

--the union of the boxes of the group's parts (get_group_descendants, element type "part"), or nil if none is readable. A group's own
--box also covers its reference points, parts' boxes only cover reference points that sit on the part itself.
-- In other words: instead of asking PYTHA for the group's own box (which can
-- balloon out to include invisible reference points), we walk every PART
-- inside the group, take EACH part's own box, and grow a running min/max
-- box to cover all of them. The result is the box of the cabinet's actual
-- material, which is what you want for finding its true centre and for
-- sizing/placing a label.
local function parts_box(group)
	local call_ok, members = pcall(function() return pytha.get_group_descendants(group) end)
	if not call_ok or type(members) ~= "table" then return nil end
	local box_min, box_max
	for _, element in ipairs(members) do
		local ok_type, kind = pcall(function() return pytha.get_element_type(element) end)
		if ok_type and kind == "part" then
			local part_box = bounding_box(element)
			if part_box ~= nil then
				if box_min == nil then
					-- first part found: this becomes the starting box
					box_min = {part_box[1][1], part_box[1][2], part_box[1][3]}
					box_max = {part_box[2][1], part_box[2][2], part_box[2][3]}
				else
					-- every later part: grow the running box to also cover it, axis by axis
					for axis = 1, 3 do
						if part_box[1][axis] < box_min[axis] then box_min[axis] = part_box[1][axis] end
						if part_box[2][axis] > box_max[axis] then box_max[axis] = part_box[2][axis] end
					end
				end
			end
		end
	end
	if box_min == nil then return nil end
	return {box_min, box_max}
end

--the box to measure a group by: the parts' box if wanted and readable, else the group's own. Second value: the group's own box.
-- Returns TWO boxes: the one actually used for numbering/centring/labelling
-- (honouring the settings.geometry_box toggle), and the group's own raw box
-- regardless of the toggle - kept around purely so the preview can show you
-- how far reference points would have shifted the centre (ref_shift_note).
local function item_box(group, settings)
	local full = bounding_box(group)
	if settings ~= nil and settings.geometry_box then
		local part_box = parts_box(group)
		if part_box ~= nil then return part_box, full end
	end
	return full, full
end

--set a group name and check that it took: a call that raises no error is not proof (found 2026-10-15: v1.4 reported
--8 names updated while the tree still showed "Base"); if the name did not change, write attribute 3 directly
local function apply_name(group, name)
	pcall(function() pytha.set_element_name(group, name) end)
	if group_name(group) == name then return true end
	-- set_element_name silently failed for this group - fall back to writing
	-- the raw "name" attribute (3) directly, which occasionally succeeds where
	-- the higher-level call doesn't.
	pcall(function() pytha.set_element_attributes(group, {[3] = name}) end)
	return group_name(group) == name
end

--the group's own rotation about its vertical axis, degrees, folded into (-180, 180]; nil if unreadable
-- "folded into (-180, 180]" means: whatever angle PYTHA reports (which could
-- be any value, e.g. 370 or -540), we normalise it into one consistent range
-- so that comparisons and the "run" bucketing in collect() behave the same
-- way regardless of how PYTHA happened to report the rotation.
local function group_angle(group, flip)
	local call_ok, angle = pcall(function() return pytha.get_group_angle(group) end)
	angle = call_ok and tonumber(angle) or nil
	if angle == nil then return nil end
	if flip then angle = -angle end
	angle = angle % 360
	if angle > 180 then angle = angle - 360 end
	return angle
end

--the direction the cabinet faces, as a unit vector in plan: angle 0 faces -y (the old assumption), +90 turns it to face +x
-- Standard 2D rotation of the vector (0,-1) by angle_deg: this is the
-- direction the FRONT of the cabinet points towards in the floor plan,
-- used both to pick which wall-run a cabinet belongs to and to work out
-- which face of the cabinet a label should sit on/face towards.
local function facing_vector(angle_deg)
	local angle_rad = math.rad(angle_deg or 0)
	return math.sin(angle_rad), -math.cos(angle_rad)
end

--every group to number: {group, box (the box it is measured by), full (the group's own box), centre_x, centre_y, tier (1 = bases, 2 = uppers),
--angle_deg, kitchen_angle_deg}
-- This is the heart of the plugin: it decides WHAT counts as a numberable
-- item and in WHAT ORDER they should be numbered.
--
-- Step 1 - gather candidates: every top-level group in the model (parent ==
-- nil), except the plugin's own "Group Numbers" label group.
--
-- Step 2 - expand kitchens: for each top-level group, check wizard_data(). If
-- it IS a Kitchen Wizard kitchen, don't number the kitchen itself - instead
-- walk its cabinet_list and number each individual cabinet inside it (bases
-- get tier 1, wall/upper cabinets - row == WALL_ROW - get tier 2). If it is
-- NOT a wizard kitchen, the group itself is the one item (tier 1).
--
-- Step 3 - order them: if settings.facing is on, items are grouped into four
-- "runs" (one per wall direction, walked clockwise: left wall, back wall,
-- right wall, front wall) using each cabinet's own rotation angle, then
-- sorted left-to-right WITHIN a run as seen from the front of the cabinets
-- (the "along" value is the cabinet's centre projected onto its own facing
-- direction). If settings.facing is off, it falls back to the simpler v1.1
-- behaviour: plain left-to-right by x coordinate.
-- Either way, bases (tier 1) are always listed before uppers (tier 2).
local function collect(settings)
	local items, skipped, kitchens = {}, 0, 0
	local use_facing = settings ~= nil and settings.facing
	local flip = settings ~= nil and settings.flip_angle
	local top = {}
	for group in pytha.enumerate_groups() do
		if pytha.get_element_parent_group(group) == nil and group_name(group) ~= LABEL_GROUP_NAME then
			table.insert(top, group)
		end
	end
	for _, group in ipairs(top) do
		local data = wizard_data(group)
		if data ~= nil then
			-- it's a Kitchen Wizard kitchen: expand it into its individual cabinets
			kitchens = kitchens + 1
			for _, spec in pairs(data.aux_values.cabinet_list) do
				local cab = type(spec) == "table" and type(spec.aux_values) == "table" and spec.aux_values.main_group or nil
				local in_kitchen = false
				if cab ~= nil then
					-- sanity check: make sure this cabinet group is actually still
					-- inside the kitchen group (it could have been moved out, or the
					-- wizard's history could be stale after manual edits)
					pcall(function() in_kitchen = (pytha.get_element_parent_group(cab) == group) end)
				end
				local box, full
				if in_kitchen then box, full = item_box(cab, settings) end
				if box ~= nil then
					local tier = (spec.aux_values.row == WALL_ROW) and 2 or 1
					table.insert(items, {group = cab, box = box, full = full, centre_x = (box[1][1] + box[2][1]) / 2, centre_y = (box[1][2] + box[2][2]) / 2, tier = tier,
						angle_deg = group_angle(cab, flip), kitchen_angle_deg = group_angle(group, flip)})
				else
					skipped = skipped + 1
				end
			end
		else
			-- a plain top-level group: it counts as one item on its own (tier 1 = base/other)
			local box, full = item_box(group, settings)
			if box ~= nil then
				table.insert(items, {group = group, box = box, full = full, centre_x = (box[1][1] + box[2][1]) / 2, centre_y = (box[1][2] + box[2][2]) / 2, tier = 1,
					angle_deg = group_angle(group, flip)})
			else
				skipped = skipped + 1
			end
		end
	end
	if use_facing then
		--bases first, then uppers. Within a tier: runs in clockwise order round the room (facing +x = left wall first, then facing -y =
		--back wall, facing -x = right wall, facing +y = front wall), then left to right as seen from the front of the cabinets.
		for _, entry in ipairs(items) do
			local angle = entry.angle_deg or 0
			-- Bucket each cabinet into one of the four 90-degree "wall runs" in
			-- clockwise order. (90 - angle) rotates our reference frame so that
			-- facing +x (left wall) comes out as run 0, facing -y (back wall) as
			-- run 90, and so on; rounding with +0.5 before the integer division
			-- keeps a cabinet that's a degree or two off a clean 0/90/180/270 in
			-- the run its angle is closest to, rather than flipping to the next
			-- run on a tiny rounding error.
			entry.run = math.floor(((90 - angle) % 360) + 0.5) % 360
			local angle_rad = math.rad(angle)
			entry.along = entry.centre_x * math.cos(angle_rad) + entry.centre_y * math.sin(angle_rad)		--position along the cabinet's own left-to-right direction
		end
		table.sort(items, function(first, second)
			if first.tier ~= second.tier then return first.tier < second.tier end
			if first.run ~= second.run then return first.run < second.run end
			if math.abs(first.along - second.along) > 1e-6 then return first.along < second.along end
			return first.box[1][3] < second.box[1][3]		--final tie-break: bottom to top
		end)
		return items, skipped, kitchens
	end
	--bases first, then uppers; each left to right by centre; ties front to back, then bottom to top
	table.sort(items, function(first, second)
		if first.tier ~= second.tier then return first.tier < second.tier end
		if math.abs(first.centre_x - second.centre_x) > 1e-6 then return first.centre_x < second.centre_x end
		if math.abs(first.box[1][2] - second.box[1][2]) > 1e-6 then return first.box[1][2] < second.box[1][2] end
		return first.box[1][3] < second.box[1][3]
	end)
	return items, skipped, kitchens
end

--two cabinets sitting on top of each other: PYTHA lets a second run be started over an existing one, and the two then get consecutive
--numbers and their labels overprint. Compares the boxes the items are measured by (the parts' boxes); returns {first, second, ratio}
--index pairs into items, ratio = shared volume / volume of the smaller box. A blind corner's L shape is measured by its square box, so a
--neighbour tucked into the blind part can be flagged: it is a warning, nothing is changed.
-- For every PAIR of items, this intersects their two boxes axis by axis
-- (standard axis-aligned-bounding-box overlap test: the overlap on each axis
-- is max(low1,low2)..min(high1,high2); if that range is non-positive on any
-- axis - beyond OVERLAP_TOL_MM of touching - the boxes don't truly overlap in
-- 3D at all). If they do overlap on all three axes, the shared volume is
-- compared against the SMALLER of the two boxes' own volumes; if that ratio
-- is at least OVERLAP_MIN_RATIO (30%), it's reported as a likely duplicate.
local function find_overlaps(items)
	local found = {}
	local tolerance = to_doc(OVERLAP_TOL_MM)
	local function volume(box) return (box[2][1] - box[1][1]) * (box[2][2] - box[1][2]) * (box[2][3] - box[1][3]) end
	for first_index = 1, #items - 1 do
		local first = items[first_index].box
		for second_index = first_index + 1, #items do
			local second = items[second_index].box
			local shared, inside = 1, true
			for axis = 1, 3 do
				local low = math.max(first[1][axis], second[1][axis])
				local high = math.min(first[2][axis], second[2][axis])
				if high - low <= tolerance then inside = false; break end
				shared = shared * (high - low)
			end
			if inside then
				local smaller = math.min(volume(first), volume(second))
				if smaller > 0 and shared / smaller >= OVERLAP_MIN_RATIO then
					table.insert(found, {first = first_index, second = second_index, ratio = shared / smaller})
				end
			end
		end
	end
	return found
end

--text lines for the overlaps; describe(entry, index) names one side
-- `describe` is a small callback so this one function can produce lines for
-- BOTH the preview (where items don't have numbers yet, so they're named by
-- row position) and the final summary (where items DO have numbers, so
-- they're named by their assigned number) without duplicating this logic.
local function overlap_lines(items, found, describe)
	local lines = {}
	if #found == 0 then return lines end
	table.insert(lines, "WARNING: " .. #found .. " pair(s) of cabinets overlap - probably a copy sitting on top of another (e.g. a second run started over an existing one):")
	for pair_number, pair in ipairs(found) do
		table.insert(lines, string.format("  %s and %s share %d%% of the smaller cabinet", describe(items[pair.first], pair.first), describe(items[pair.second], pair.second), math.floor(pair.ratio * 100 + 0.5)))
		if pair_number >= 8 then
			-- don't let one messy file turn the alert box into a huge wall of text
			table.insert(lines, "  ... " .. (#found - 8) .. " more")
			break
		end
	end
	return lines
end

-- Builds the options dialog for "Number Groups". `dialog` is PYTHA's dialog-
-- builder object; `settings` is the live settings table (loaded by
-- load_settings, mutated in place by the control callbacks below, and saved
-- back to disk by number_groups() once the user clicks OK).
function numbering_dialog(dialog, settings)
	dialog:set_window_title(pyloc "Group Numbering 1.7")
	dialog:create_standalone_label({1, 2}, pyloc "Bases, then uppers, in order round the room (by facing). Existing numbers are kept.")

	local renumber = dialog:create_check_box({1, 2}, pyloc "Renumber everything (restart at the start number)")
	renumber:set_control_checked(settings.renumber_all)
	renumber:set_on_click_handler(function(state) settings.renumber_all = state end)

	dialog:create_label(1, pyloc "Start at")
	local start = dialog:create_text_box(2, pyui.format_number(settings.start))
	start:set_on_change_handler(function(text)
		local typed_number = pyui.parse_number(text)
		if typed_number ~= nil and typed_number >= 1 then
			settings.start = math.floor(typed_number)
		end
	end)

	local facing = dialog:create_check_box({1, 2}, pyloc "Order by each cabinet's facing (runs along any wall); untick for left to right along x")
	facing:set_control_checked(settings.facing)
	facing:set_on_click_handler(function(state) settings.facing = state end)

	local geometry_check = dialog:create_check_box({1, 2}, pyloc "Use the parts' own box for centres and labels (ignores reference points; untick for the group's own box)")
	geometry_check:set_control_checked(settings.geometry_box)
	geometry_check:set_on_click_handler(function(state) settings.geometry_box = state end)

	local flip = dialog:create_check_box({1, 2}, pyloc "Flip the angle sign (if the preview shows the rotation the other way round)")
	flip:set_control_checked(settings.flip_angle)
	flip:set_on_click_handler(function(state) settings.flip_angle = state end)

	local preview = dialog:create_check_box({1, 2}, pyloc "Preview the order only (lists numbers and angles, changes nothing)")
	preview:set_control_checked(settings.preview)
	preview:set_on_click_handler(function(state) settings.preview = state end)

	local rename = dialog:create_check_box({1, 2}, pyloc "Add the number to the group name (Base #3)")
	rename:set_control_checked(settings.rename)
	rename:set_on_click_handler(function(state) settings.rename = state end)

	local labels = dialog:create_check_box({1, 2}, pyloc "Place 3D number labels")
	labels:set_control_checked(settings.labels)

	dialog:create_label(1, pyloc "Label height")
	local height = dialog:create_text_box(2, pyui.format_length(to_doc(settings.label_height_mm)))
	height:set_on_change_handler(function(text)
		local typed_length = pyui.parse_length(text)
		if typed_length ~= nil and typed_length > 0 then
			settings.label_height_mm = to_mm(typed_length)
		end
	end)

	dialog:create_label(1, pyloc "Label layer (0 = active)")
	local layer = dialog:create_text_box(2, pyui.format_number(settings.layer))
	layer:set_on_change_handler(function(text)
		local typed_number = pyui.parse_number(text)
		if typed_number ~= nil and typed_number >= 0 and typed_number <= 256 then
			settings.layer = math.floor(typed_number)
		end
	end)

	-- The pen (colour) picker is a checkbox + a drop-list. The checkbox is the
	-- on/off toggle (settings.pen == 0 means "leave PYTHA's current pen
	-- alone"); the drop-list remembers the last pen chosen (pen_choice) even
	-- while the checkbox is unticked, so re-ticking it restores your last pick
	-- instead of resetting to pen 1.
	local pen_check = dialog:create_check_box(1, pyloc "Label pen (colour)")
	pen_check:set_control_checked(settings.pen > 0)
	local pen = dialog:create_pen_list(2)
	pen:set_control_selection(settings.pen > 0 and settings.pen or 1)
	pen:set_on_change_handler(function(text, new_index)
		local typed_pen = new_index or tonumber(text)
		if typed_pen ~= nil and typed_pen >= 1 and typed_pen <= 256 then
			settings.pen_choice = math.floor(typed_pen)
			if settings.pen > 0 then settings.pen = settings.pen_choice end
		end
	end)
	pen_check:set_on_click_handler(function(state)
		if state then
			settings.pen = settings.pen_choice or (settings.pen > 0 and settings.pen) or 1
			pen:enable_control()
		else
			settings.pen = 0
			pen:disable_control()
		end
	end)
	if settings.pen == 0 then pen:disable_control() end

	-- The label-related controls (height/layer/pen) only make sense when
	-- "Place 3D number labels" is ticked, so this greys them out together
	-- whenever that checkbox is off.
	local function enable_label_options(state)
		if state then
			height:enable_control(); layer:enable_control(); pen_check:enable_control()
			if settings.pen > 0 then pen:enable_control() end
		else
			height:disable_control(); layer:disable_control(); pen_check:disable_control(); pen:disable_control()
		end
	end
	labels:set_on_click_handler(function(state)
		settings.labels = state
		enable_label_options(state)
	end)
	if not settings.labels then enable_label_options(false) end

	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

-- Creates one 3D text label (the cabinet's number) standing upright on the
-- front face of its box, facing the same way the cabinet does.
--
-- The geometry: `across` is the left-to-right direction as seen from the
-- front of the cabinet (used to orient and later centre the text), `front`
-- is the direction the cabinet's front face points towards (used to find
-- where the front face is and to tilt the label to face outward). half_depth
-- projects the box's half-size onto the front direction, which is how we
-- find the front face regardless of which way the box happens to be
-- rotated. push_local_coordinates/pop_local_coordinates temporarily moves
-- PYTHA's working coordinate system to this custom orientation so
-- create_text_3d (which always writes text flat along its own local axes)
-- comes out upright and correctly rotated in world space.
local function place_label(text, entry, settings)
	local box = entry.box
	local label_height = to_doc(settings.label_height_mm)
	local thickness = label_height / 10
	local angle_deg = settings.facing and (entry.angle_deg or 0) or 0
	local angle_rad = math.rad(angle_deg)
	local across_x, across_y = math.cos(angle_rad), math.sin(angle_rad)				--left to right as seen from the front
	local front_x, front_y = facing_vector(angle_deg)					--the direction the front looks
	local centre_x, centre_y = (box[1][1] + box[2][1]) / 2, (box[1][2] + box[2][2]) / 2
	local size_x, size_y = box[2][1] - box[1][1], box[2][2] - box[1][2]
	local half_depth = (math.abs(front_x) * size_x + math.abs(front_y) * size_y) / 2		--front face of the box, along the facing direction
	local origin = {centre_x + front_x * half_depth, centre_y + front_y * half_depth, box[2][3] + to_doc(settings.label_gap_mm)}
	--upright, reading from the front: letters in the plane across the cabinet, extruded away from the front
	local token = pytha.push_local_coordinates(origin, {u_axis = {across_x, across_y, 0}, v_axis = {0, 0, 1}, w_axis = {front_x, front_y, 0}})
	local call_ok, label = pcall(function() return pytha.create_text_3d(text, label_height, thickness) end)
	pytha.pop_local_coordinates(token)
	if not call_ok then
		error(label, 0)
	end
	--the text now exists in the model: if any step below fails, delete it so no stray label is left behind
	local ok_steps, steps_error = pcall(function()
		--create_text_3d starts the text at the origin; centre it over the group along the left-to-right direction
		local label_box = pytha.get_element_bounding_box(label)
		local width = math.abs(across_x) * (label_box[2][1] - label_box[1][1]) + math.abs(across_y) * (label_box[2][2] - label_box[1][2])
		pytha.move_element(label, {-across_x * width / 2, -across_y * width / 2, 0})
		pytha.set_element_name(label, LABEL_PREFIX .. text)
		if settings.layer > 0 then
			pytha.set_element_layer(label, settings.layer)
		end
		if settings.pen > 0 then
			pytha.set_element_pen(label, settings.pen)	--a part with no material shows in its pen colour
		end
	end)
	if not ok_steps then
		-- something after the text was created failed (e.g. couldn't set the
		-- layer/pen) - clean up the half-finished label rather than leaving an
		-- orphaned 3D text object floating in the model, then re-raise so the
		-- caller in number_groups() can count it as a failure.
		pcall(pytha.delete_element, label)
		error(steps_error, 0)
	end
	return label
end

--preview note: how far the group's own box centre (reference points included) sits from the parts' box centre
local function ref_shift_note(entry)
	if entry.full == nil or entry.box == entry.full then return "" end
	local front_x = (entry.full[1][1] + entry.full[2][1]) / 2 - entry.centre_x
	local front_y = (entry.full[1][2] + entry.full[2][2]) / 2 - entry.centre_y
	if math.abs(front_x) < 0.05 and math.abs(front_y) < 0.05 then return "" end
	return string.format("   (reference points would shift the centre by %.1f, %.1f)", front_x, front_y)
end

-- MAIN ACTION: "Number Groups". Shows the options dialog, then either just
-- previews the order (changes nothing) or actually numbers/renames/labels
-- every cabinet, in five stages:
--   1. collect() every item and decide the order (see collect() above)
--   2. decide numbers: keep each item's existing number if it still has one
--      and that number hasn't already been claimed by an earlier item in the
--      list; otherwise hand out the next free number above the highest one
--      in use
--   3. write attribute 46 (position number) on every item's group
--   4. optionally rewrite the group's name and/or place a 3D label
--   5. build and show a plain-text summary, including any overlap warnings
function number_groups()
	local settings = load_settings()
	if pyui.run_modal_subdialog(numbering_dialog, settings) ~= "ok" then
		return		-- user cancelled the dialog: do nothing at all
	end
	local renumber_all = settings.renumber_all
	settings.pen_choice = nil		--a UI-only scratch value; never worth persisting
	pyio.save_values("numbering_settings", settings)

	if settings.preview then
		-- PREVIEW MODE: run the same collect() the real pass would use, but
		-- only print what the order/angles/centres would be - nothing in the
		-- model is touched. This is how you sanity-check "facing" and "flip the
		-- angle sign" before committing to a real run.
		local pitems = collect(settings)
		local rows = {pyloc "Group Numbering - preview (nothing changed)", "unit " .. pytha.get_length_unit() .. "; facing " .. (settings.facing and "on" or "off") .. (settings.flip_angle and ", angle flipped" or ""), ""}
		for row_number, entry in ipairs(pitems) do
			local display_name = group_name(entry.group)
			table.insert(rows, string.format("%d. %s   angle %s%s   centre %.0f, %.0f   %s", row_number, display_name == "" and "(unnamed)" or display_name,
				entry.angle_deg and string.format("%.1f", entry.angle_deg) or "?", entry.kitchen_angle_deg and string.format(" (kitchen %.1f)", entry.kitchen_angle_deg) or "",
				entry.centre_x, entry.centre_y, entry.tier == 2 and "upper" or "base") .. ref_shift_note(entry))
			if row_number >= 40 then table.insert(rows, "... " .. (#pitems - 40) .. " more"); break end
		end
		local overlap_rows = overlap_lines(pitems, find_overlaps(pitems), function(entry, row_number)
			local display_name = group_name(entry.group)
			return string.format("%d (%s)", row_number, display_name == "" and "unnamed" or display_name)
		end)
		if #overlap_rows > 0 then
			table.insert(rows, "")
			for _, row in ipairs(overlap_rows) do table.insert(rows, row) end
		end
		pyui.alert(table.concat(rows, "\n"))
		-- also drop a copy in PYTHA's scratch folder, so a long preview that
		-- scrolled off the alert box can still be read afterwards
		pcall(function() pyio.write_lines(pyio.get_scratch_folder_path("group_numbering_preview.txt"), rows) end)
		return
	end
	-- REAL RUN starts here: clear any labels from a previous run first, so this
	-- run's labels never stack on top of stale ones.
	local removed = delete_labels()
	local items, skipped, kitchens = collect(settings)
	if #items == 0 then
		pyui.alert(pyloc "Group Numbering: nothing to number (no cabinets or top-level groups found).")
		return
	end

	--keep existing numbers (left to right, the first holder of a number keeps it); everything else gets
	--the next free number above the highest one in use
	local used, kept = {}, 0
	local highest = settings.start - 1
	if not renumber_all then
		-- First pass: walk items in order and let each one keep its OLD number,
		-- but only if that number hasn't already been claimed by an earlier
		-- item in the list (so if two items somehow share a stale number, the
		-- leftmost/earliest one wins it and the other gets treated as unnumbered
		-- below). Also tracks `highest`, the biggest number already in use, so
		-- new numbers start above it rather than colliding.
		for _, entry in ipairs(items) do
			local number = existing_number(entry.group)
			if number ~= nil and not used[number] then
				used[number] = true
				entry.number = number
				kept = kept + 1
				if number > highest then highest = number end
			end
		end
	end
	-- Second pass: give every item that didn't keep an old number the next
	-- free integer above `highest`, skipping any number already claimed in
	-- the first pass.
	local next_free = highest + 1
	local assigned = 0
	for _, entry in ipairs(items) do
		if entry.number == nil then
			while used[next_free] do next_free = next_free + 1 end
			entry.number = next_free
			used[next_free] = true
			next_free = next_free + 1
			assigned = assigned + 1
		end
	end

	-- Now actually write the results into the model: the position-number
	-- attribute always, the name and the 3D label only if those options are
	-- ticked. Every step is counted so the summary at the end can tell the
	-- user exactly what happened and what (if anything) didn't stick.
	local failed, renamed, labels, label_errors = 0, 0, {}, 0
	local rename_failed, rename_example = 0, nil
	for _, entry in ipairs(items) do
		local number = entry.number
		if not pcall(function() pytha.set_element_attributes(entry.group, {[46] = number}) end) then
			failed = failed + 1
		end
		if settings.rename then
			local want = base_name(group_name(entry.group)) .. NAME_SEPARATOR .. number
			if apply_name(entry.group, want) then
				renamed = renamed + 1
			else
				rename_failed = rename_failed + 1
				if rename_example == nil then rename_example = {want = want, got = group_name(entry.group)} end
			end
		end
		if settings.labels then
			local ok_label, label = pcall(function() return place_label(tostring(number), entry, settings) end)
			if ok_label and label ~= nil then
				table.insert(labels, label)
			else
				label_errors = label_errors + 1
			end
		end
	end
	if #labels > 0 then
		-- gather every label this run created into one top-level group, named
		-- LABEL_GROUP_NAME, so find_label_groups()/delete_labels() can find and
		-- remove them all together on the next run or on "Remove number labels"
		pytha.create_group(labels, {name = LABEL_GROUP_NAME})
	end

	-- Build the plain-text result message shown in the alert box, piece by
	-- piece depending on which options were used and whether anything failed.
	local bases, uppers = 0, 0
	for _, entry in ipairs(items) do
		if entry.tier == 2 then uppers = uppers + 1 else bases = bases + 1 end
	end
	local msg = {pyloc "Group Numbering", ""}
	table.insert(msg, #items .. " cabinet(s)/group(s): " .. bases .. " base / other, " .. uppers .. " upper" .. (kitchens > 0 and (", from " .. kitchens .. " Kitchen Wizard kitchen(s)") or "") .. ".")
	if renumber_all then
		table.insert(msg, "Renumbered everything from " .. settings.start .. ".")
	else
		table.insert(msg, kept .. " kept their number, " .. assigned .. " got a new one.")
	end
	if settings.rename then
		table.insert(msg, renamed .. " group name(s) updated (e.g. 'Base #3').")
		if rename_failed > 0 then
			table.insert(msg, rename_failed .. " group name(s) did not stick: wanted '" .. rename_example.want .. "', PYTHA still has '" .. rename_example.got .. "'.")
		end
	end
	if failed > 0 then table.insert(msg, "Could not write the position number on " .. failed .. " group(s).") end
	if skipped > 0 then table.insert(msg, skipped .. " group(s) without geometry were skipped.") end
	if settings.labels then
		table.insert(msg, #labels .. " label(s) placed in the group '" .. LABEL_GROUP_NAME .. "'" .. (settings.layer > 0 and (" on layer " .. settings.layer) or "") .. ".")
		if label_errors > 0 then table.insert(msg, label_errors .. " label(s) could not be placed.") end
	end
	if removed > 0 then table.insert(msg, "Old labels replaced.") end
	local overlap_rows = overlap_lines(items, find_overlaps(items), function(entry)
		return string.format("%d (%s)", entry.number, group_name(entry.group))
	end)
	if #overlap_rows > 0 then
		table.insert(msg, "")
		for _, row in ipairs(overlap_rows) do table.insert(msg, row) end
	end
	table.insert(msg, "")
	table.insert(msg, "A Kitchen Wizard Edit rebuilds the kitchen: its cabinets lose their numbers and get new ones on the next run.")
	pyui.alert(table.concat(msg, "\n"))
end

-- "Remove number labels" action: deletes the 3D labels only. Position
-- numbers (attribute 46) and group names are left untouched, so the
-- underlying numbering survives even if you don't want the 3D text in the
-- model right now.
function remove_labels()
	local removed = delete_labels()
	if removed > 0 then
		pyui.alert(pyloc "Group Numbering: number labels removed. Position numbers and names stay on the groups.")
	else
		pyui.alert(pyloc "Group Numbering: no number labels found.")
	end
end

--============================================================
-- The one menu entry: a picker for the actions
--============================================================
-- PYTHA's plugin sidebar only shows a limited number of entries in total, so
-- rather than registering "Number Groups" and "Remove number labels" as two
-- separate plugin menu items, this plugin registers ONE entry
-- (numbering_launcher, below) that opens a small picker dialog letting the
-- user choose which of the two actions to run. The picker remembers the last
-- action chosen (LAUNCHER_STORE) so it defaults to whatever you used last
-- time.
local LAUNCHER_STORE = "Group_numbering_launcher"

-- The list of {caption, function_to_call, description} the picker offers.
local function launcher_actions()
	return {
		{pyloc "Number Groups", number_groups, pyloc "Number every top-level group in order round the room and (optionally) label it. Run again after any change - old labels are replaced."},
		{pyloc "Remove number labels", remove_labels, pyloc "Delete the 3D number labels. Position numbers stay on the groups."},
	}
end

-- Builds the small picker dialog: a drop-list of action names, plus a label
-- underneath that updates to show that action's description as you change
-- the selection.
local function launcher_dialog(dialog, launcher)
	dialog:set_window_title(pyloc "Group Numbering 1.7")
	dialog:create_label(1, pyloc "Action")
	local list = dialog:create_drop_list(2)
	for _, action in ipairs(launcher.actions) do
		list:insert_control_item(action[1])
	end
	list:set_control_selection(launcher.pick)
	local info = dialog:create_label({1, 2}, launcher.actions[launcher.pick][3])
	list:set_on_change_handler(function(text, index)
		local chosen_index = tonumber(index)
		if chosen_index == nil then
			-- some PYTHA versions report the change by text instead of index;
			-- fall back to matching the caption text against the action list
			for action_index, action in ipairs(launcher.actions) do
				if action[1] == text then chosen_index = action_index end
			end
		end
		if chosen_index ~= nil and launcher.actions[chosen_index] ~= nil then
			launcher.pick = chosen_index
			info:set_control_text(launcher.actions[chosen_index][3])
		end
	end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

-- This is the function PYTHA's plugin sidebar actually calls (the single
-- registered entry-point, see config.xml). It shows the picker, remembers
-- which action was last chosen, and then calls that action's function.
function numbering_launcher()
	local launcher = {pick = 1, actions = launcher_actions()}
	local ok_load, saved = pcall(function() return pyio.load_values(LAUNCHER_STORE) end)
	if ok_load and type(saved) == "table" and launcher.actions[tonumber(saved.pick) or 0] ~= nil then
		launcher.pick = tonumber(saved.pick)
	end
	if pyui.run_modal_subdialog(launcher_dialog, launcher) ~= "ok" then
		return
	end
	pcall(function() pyio.save_values(LAUNCHER_STORE, {pick = launcher.pick}) end)
	launcher.actions[launcher.pick][2]()
end

-- Group Numbering v1.7 (2026-10-16) - centres and labels now come from the box of the group's PARTS, not the group's own bounding box.
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

local LABEL_GROUP_NAME = "Group Numbers"		--all labels live in this one top-level group, never inside the numbered groups
local LABEL_PREFIX = "Group No. "
local NAME_SEPARATOR = " #"					--"Base" -> "Base #3"
local WIZARD_HISTORY_KEYS = {"wizard_history"}	--Kitchen Wizard's element-history key
local WALL_ROW = 0x2						--Kitchen Wizard row code for wall cabinets

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

local function to_doc(v_mm)
	if pytha.get_length_unit() == "in" then
		return v_mm / 25.4
	end
	return v_mm
end

local function to_mm(v_doc)
	if pytha.get_length_unit() == "in" then
		return v_doc * 25.4
	end
	return v_doc
end

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

local function find_label_groups()
	local found = {}
	for group in pytha.enumerate_groups() do
		if pytha.get_element_parent_group(group) == nil and group_name(group) == LABEL_GROUP_NAME then
			table.insert(found, group)
		end
	end
	return found
end

local function delete_labels()
	local old = find_label_groups()
	if #old > 0 then
		pytha.delete_element(old)
	end
	return #old
end

--the wizard's own data on a kitchen group, or nil for any other group
local function wizard_data(group)
	for _, key in ipairs(WIZARD_HISTORY_KEYS) do
		local call_ok, data = pcall(function() return pytha.get_element_history(group, key) end)
		if call_ok and type(data) == "table" and type(data.aux_values) == "table" and type(data.aux_values.cabinet_list) == "table" then
			return data
		end
	end
	return nil
end

local function bounding_box(group)
	local call_ok, box = pcall(function() return pytha.get_element_bounding_box(group) end)
	if call_ok and type(box) == "table" and box[1] ~= nil and box[2] ~= nil then
		return box
	end
	return nil
end

--the union of the boxes of the group's parts (get_group_descendants, element type "part"), or nil if none is readable. A group's own
--box also covers its reference points, parts' boxes only cover reference points that sit on the part itself.
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
					box_min = {part_box[1][1], part_box[1][2], part_box[1][3]}
					box_max = {part_box[2][1], part_box[2][2], part_box[2][3]}
				else
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
	pcall(function() pytha.set_element_attributes(group, {[3] = name}) end)
	return group_name(group) == name
end

--the group's own rotation about its vertical axis, degrees, folded into (-180, 180]; nil if unreadable
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
local function facing_vector(angle_deg)
	local angle_rad = math.rad(angle_deg or 0)
	return math.sin(angle_rad), -math.cos(angle_rad)
end

--every group to number: {group, box (the box it is measured by), full (the group's own box), centre_x, centre_y, tier (1 = bases, 2 = uppers),
--angle_deg, kitchen_angle_deg}
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
			kitchens = kitchens + 1
			for _, spec in pairs(data.aux_values.cabinet_list) do
				local cab = type(spec) == "table" and type(spec.aux_values) == "table" and spec.aux_values.main_group or nil
				local in_kitchen = false
				if cab ~= nil then
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
			entry.run = math.floor(((90 - angle) % 360) + 0.5) % 360
			local angle_rad = math.rad(angle)
			entry.along = entry.centre_x * math.cos(angle_rad) + entry.centre_y * math.sin(angle_rad)		--position along the cabinet's own left-to-right direction
		end
		table.sort(items, function(first, second)
			if first.tier ~= second.tier then return first.tier < second.tier end
			if first.run ~= second.run then return first.run < second.run end
			if math.abs(first.along - second.along) > 1e-6 then return first.along < second.along end
			return first.box[1][3] < second.box[1][3]
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

function number_groups()
	local settings = load_settings()
	if pyui.run_modal_subdialog(numbering_dialog, settings) ~= "ok" then
		return
	end
	local renumber_all = settings.renumber_all
	settings.pen_choice = nil
	pyio.save_values("numbering_settings", settings)

	if settings.preview then
		local pitems = collect(settings)
		local rows = {pyloc "Group Numbering - preview (nothing changed)", "unit " .. pytha.get_length_unit() .. "; facing " .. (settings.facing and "on" or "off") .. (settings.flip_angle and ", angle flipped" or ""), ""}
		for row_number, entry in ipairs(pitems) do
			local display_name = group_name(entry.group)
			table.insert(rows, string.format("%d. %s   angle %s%s   centre %.0f, %.0f   %s", row_number, display_name == "" and "(unnamed)" or display_name,
				entry.angle_deg and string.format("%.1f", entry.angle_deg) or "?", entry.kitchen_angle_deg and string.format(" (kitchen %.1f)", entry.kitchen_angle_deg) or "",
				entry.centre_x, entry.centre_y, entry.tier == 2 and "upper" or "base") .. ref_shift_note(entry))
			if row_number >= 40 then table.insert(rows, "... " .. (#pitems - 40) .. " more"); break end
		end
		pyui.alert(table.concat(rows, "\n"))
		pcall(function() pyio.write_lines(pyio.get_scratch_folder_path("group_numbering_preview.txt"), rows) end)
		return
	end
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
		pytha.create_group(labels, {name = LABEL_GROUP_NAME})
	end

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
	table.insert(msg, "")
	table.insert(msg, "A Kitchen Wizard Edit rebuilds the kitchen: its cabinets lose their numbers and get new ones on the next run.")
	pyui.alert(table.concat(msg, "\n"))
end

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
local LAUNCHER_STORE = "Group_numbering_launcher"

local function launcher_actions()
	return {
		{pyloc "Number Groups", number_groups, pyloc "Number every top-level group in order round the room and (optionally) label it. Run again after any change - old labels are replaced."},
		{pyloc "Remove number labels", remove_labels, pyloc "Delete the 3D number labels. Position numbers stay on the groups."},
	}
end

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

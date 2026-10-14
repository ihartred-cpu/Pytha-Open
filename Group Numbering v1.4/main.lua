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
local WIZARD_HISTORY_KEYS = {"wizard_history", "Group_cabinet_wizard_history"}	--KWGUID build / standalone build
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
	local s = {}
	for k, v in pairs(DEFAULTS) do
		s[k] = v
	end
	local saved = pyio.load_values("numbering_settings")
	if type(saved) == "table" then
		for k, v in pairs(saved) do
			if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then
				s[k] = v
			end
		end
	end
	s.renumber_all = false		--never remembered: a full renumber must be asked for each time
	s.pen_choice = nil
	return s
end

local function group_name(g)
	local ok, n = pcall(function() return pytha.get_element_attribute(g, 3) end)
	if ok and n ~= nil then
		return tostring(n)
	end
	return ""
end

local function base_name(name)
	--strip a number added by an earlier run ("Base #3" -> "Base")
	return (name:gsub(" #%d+$", ""))
end

local function existing_number(g)
	local ok, v = pcall(function() return pytha.get_element_attribute(g, 46) end)
	if not ok or v == nil then
		return nil
	end
	local n = tonumber(v)
	if n ~= nil and n >= 1 and n == math.floor(n) then
		return math.floor(n)		--integer: PYTHA hands attributes back as text, e.g. "40.0" -> 40, never "Base #40.0"
	end
	return nil
end

local function find_label_groups()
	local found = {}
	for g in pytha.enumerate_groups() do
		if pytha.get_element_parent_group(g) == nil and group_name(g) == LABEL_GROUP_NAME then
			table.insert(found, g)
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
local function wizard_data(g)
	for _, key in ipairs(WIZARD_HISTORY_KEYS) do
		local ok, data = pcall(function() return pytha.get_element_history(g, key) end)
		if ok and type(data) == "table" and type(data.aux_values) == "table" and type(data.aux_values.cabinet_list) == "table" then
			return data
		end
	end
	return nil
end

local function bounding_box(g)
	local ok, bb = pcall(function() return pytha.get_element_bounding_box(g) end)
	if ok and type(bb) == "table" and bb[1] ~= nil and bb[2] ~= nil then
		return bb
	end
	return nil
end

--every group to number: {group, bb, cx, tier (1 = bases, 2 = uppers)}
local function collect()
	local items, skipped, kitchens = {}, 0, 0
	local top = {}
	for g in pytha.enumerate_groups() do
		if pytha.get_element_parent_group(g) == nil and group_name(g) ~= LABEL_GROUP_NAME then
			table.insert(top, g)
		end
	end
	for _, g in ipairs(top) do
		local data = wizard_data(g)
		if data ~= nil then
			kitchens = kitchens + 1
			for _, spec in pairs(data.aux_values.cabinet_list) do
				local cab = type(spec) == "table" and type(spec.aux_values) == "table" and spec.aux_values.main_group or nil
				local in_kitchen = false
				if cab ~= nil then
					pcall(function() in_kitchen = (pytha.get_element_parent_group(cab) == g) end)
				end
				local bb = in_kitchen and bounding_box(cab) or nil
				if bb ~= nil then
					local tier = (spec.aux_values.row == WALL_ROW) and 2 or 1
					table.insert(items, {group = cab, bb = bb, cx = (bb[1][1] + bb[2][1]) / 2, tier = tier})
				else
					skipped = skipped + 1
				end
			end
		else
			local bb = bounding_box(g)
			if bb ~= nil then
				table.insert(items, {group = g, bb = bb, cx = (bb[1][1] + bb[2][1]) / 2, tier = 1})
			else
				skipped = skipped + 1
			end
		end
	end
	--bases first, then uppers; each left to right by centre; ties front to back, then bottom to top
	table.sort(items, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		if math.abs(a.cx - b.cx) > 1e-6 then return a.cx < b.cx end
		if math.abs(a.bb[1][2] - b.bb[1][2]) > 1e-6 then return a.bb[1][2] < b.bb[1][2] end
		return a.bb[1][3] < b.bb[1][3]
	end)
	return items, skipped, kitchens
end

function numbering_dialog(dialog, s)
	dialog:set_window_title(pyloc "Group Numbering 1.4")
	dialog:create_standalone_label({1, 2}, pyloc "Bases, then uppers, left to right. Existing numbers are kept.")

	local renumber = dialog:create_check_box({1, 2}, pyloc "Renumber everything (restart at the start number)")
	renumber:set_control_checked(s.renumber_all)
	renumber:set_on_click_handler(function(state) s.renumber_all = state end)

	dialog:create_label(1, pyloc "Start at")
	local start = dialog:create_text_box(2, pyui.format_number(s.start))
	start:set_on_change_handler(function(text)
		local n = pyui.parse_number(text)
		if n ~= nil and n >= 1 then
			s.start = math.floor(n)
		end
	end)

	local rename = dialog:create_check_box({1, 2}, pyloc "Add the number to the group name (Base #3)")
	rename:set_control_checked(s.rename)
	rename:set_on_click_handler(function(state) s.rename = state end)

	local labels = dialog:create_check_box({1, 2}, pyloc "Place 3D number labels")
	labels:set_control_checked(s.labels)

	dialog:create_label(1, pyloc "Label height")
	local height = dialog:create_text_box(2, pyui.format_length(to_doc(s.label_height_mm)))
	height:set_on_change_handler(function(text)
		local v = pyui.parse_length(text)
		if v ~= nil and v > 0 then
			s.label_height_mm = to_mm(v)
		end
	end)

	dialog:create_label(1, pyloc "Label layer (0 = active)")
	local layer = dialog:create_text_box(2, pyui.format_number(s.layer))
	layer:set_on_change_handler(function(text)
		local n = pyui.parse_number(text)
		if n ~= nil and n >= 0 and n <= 256 then
			s.layer = math.floor(n)
		end
	end)

	local pen_check = dialog:create_check_box(1, pyloc "Label pen (colour)")
	pen_check:set_control_checked(s.pen > 0)
	local pen = dialog:create_pen_list(2)
	pen:set_control_selection(s.pen > 0 and s.pen or 1)
	pen:set_on_change_handler(function(text, new_index)
		local n = new_index or tonumber(text)
		if n ~= nil and n >= 1 and n <= 256 then
			s.pen_choice = math.floor(n)
			if s.pen > 0 then s.pen = s.pen_choice end
		end
	end)
	pen_check:set_on_click_handler(function(state)
		if state then
			s.pen = s.pen_choice or (s.pen > 0 and s.pen) or 1
			pen:enable_control()
		else
			s.pen = 0
			pen:disable_control()
		end
	end)
	if s.pen == 0 then pen:disable_control() end

	local function enable_label_options(state)
		if state then
			height:enable_control(); layer:enable_control(); pen_check:enable_control()
			if s.pen > 0 then pen:enable_control() end
		else
			height:disable_control(); layer:disable_control(); pen_check:disable_control(); pen:disable_control()
		end
	end
	labels:set_on_click_handler(function(state)
		s.labels = state
		enable_label_options(state)
	end)
	if not s.labels then enable_label_options(false) end

	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

local function place_label(text, bb, s)
	local h = to_doc(s.label_height_mm)
	local thickness = h / 10
	local cx = (bb[1][1] + bb[2][1]) / 2
	local origin = {cx, bb[1][2], bb[2][3] + to_doc(s.label_gap_mm)}
	--upright, reading from the front: letters in the x-z plane, extruded toward -y
	local token = pytha.push_local_coordinates(origin, {u_axis = {1, 0, 0}, v_axis = {0, 0, 1}, w_axis = {0, -1, 0}})
	local ok, label = pcall(function() return pytha.create_text_3d(text, h, thickness) end)
	pytha.pop_local_coordinates(token)
	if not ok then
		error(label)
	end
	--create_text_3d starts the text at the origin; centre it over the group
	local lb = pytha.get_element_bounding_box(label)
	pytha.move_element(label, {cx - (lb[1][1] + lb[2][1]) / 2, 0, 0})
	pytha.set_element_name(label, LABEL_PREFIX .. text)
	if s.layer > 0 then
		pytha.set_element_layer(label, s.layer)
	end
	if s.pen > 0 then
		pytha.set_element_pen(label, s.pen)	--a part with no material shows in its pen colour
	end
	return label
end

function number_groups()
	local s = load_settings()
	if pyui.run_modal_subdialog(numbering_dialog, s) ~= "ok" then
		return
	end
	local renumber_all = s.renumber_all
	s.pen_choice = nil
	pyio.save_values("numbering_settings", s)

	local removed = delete_labels()
	local items, skipped, kitchens = collect()
	if #items == 0 then
		pyui.alert(pyloc "Group Numbering: nothing to number (no cabinets or top-level groups found).")
		return
	end

	--keep existing numbers (left to right, the first holder of a number keeps it); everything else gets
	--the next free number above the highest one in use
	local used, kept = {}, 0
	local highest = s.start - 1
	if not renumber_all then
		for _, it in ipairs(items) do
			local n = existing_number(it.group)
			if n ~= nil and not used[n] then
				used[n] = true
				it.number = n
				kept = kept + 1
				if n > highest then highest = n end
			end
		end
	end
	local next_free = highest + 1
	local assigned = 0
	for _, it in ipairs(items) do
		if it.number == nil then
			while used[next_free] do next_free = next_free + 1 end
			it.number = next_free
			used[next_free] = true
			next_free = next_free + 1
			assigned = assigned + 1
		end
	end

	local failed, renamed, labels, label_errors = 0, 0, {}, 0
	for _, it in ipairs(items) do
		local n = it.number
		if not pcall(function() pytha.set_element_attributes(it.group, {[46] = n}) end) then
			failed = failed + 1
		end
		if s.rename then
			local ok = pcall(function()
				pytha.set_element_name(it.group, base_name(group_name(it.group)) .. NAME_SEPARATOR .. n)
			end)
			if ok then renamed = renamed + 1 end
		end
		if s.labels then
			local okl, label = pcall(function() return place_label(tostring(n), it.bb, s) end)
			if okl and label ~= nil then
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
	for _, it in ipairs(items) do
		if it.tier == 2 then uppers = uppers + 1 else bases = bases + 1 end
	end
	local msg = {pyloc "Group Numbering", ""}
	table.insert(msg, #items .. " cabinet(s)/group(s): " .. bases .. " base / other, " .. uppers .. " upper" .. (kitchens > 0 and (", from " .. kitchens .. " Kitchen Wizard kitchen(s)") or "") .. ".")
	if renumber_all then
		table.insert(msg, "Renumbered everything from " .. s.start .. ".")
	else
		table.insert(msg, kept .. " kept their number, " .. assigned .. " got a new one.")
	end
	if s.rename then table.insert(msg, renamed .. " group name(s) updated (e.g. 'Base #3').") end
	if failed > 0 then table.insert(msg, "Could not write the position number on " .. failed .. " group(s).") end
	if skipped > 0 then table.insert(msg, skipped .. " group(s) without geometry were skipped.") end
	if s.labels then
		table.insert(msg, #labels .. " label(s) placed in the group '" .. LABEL_GROUP_NAME .. "'" .. (s.layer > 0 and (" on layer " .. s.layer) or "") .. ".")
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
		{pyloc "Number Groups", number_groups, pyloc "Number every top-level group left to right and (optionally) label it. Run again after any change - old labels are replaced."},
		{pyloc "Remove number labels", remove_labels, pyloc "Delete the 3D number labels. Position numbers stay on the groups."},
	}
end

local function launcher_dialog(dialog, st)
	dialog:set_window_title(pyloc "Group Numbering 1.4")
	dialog:create_label(1, pyloc "Action")
	local list = dialog:create_drop_list(2)
	for _, a in ipairs(st.actions) do
		list:insert_control_item(a[1])
	end
	list:set_control_selection(st.pick)
	local info = dialog:create_label({1, 2}, st.actions[st.pick][3])
	list:set_on_change_handler(function(text, index)
		local i = tonumber(index)
		if i == nil then
			for n, a in ipairs(st.actions) do
				if a[1] == text then i = n end
			end
		end
		if i ~= nil and st.actions[i] ~= nil then
			st.pick = i
			info:set_control_text(st.actions[i][3])
		end
	end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

function numbering_launcher()
	local st = {pick = 1, actions = launcher_actions()}
	local ok_load, saved = pcall(function() return pyio.load_values(LAUNCHER_STORE) end)
	if ok_load and type(saved) == "table" and st.actions[tonumber(saved.pick) or 0] ~= nil then
		st.pick = tonumber(saved.pick)
	end
	if pyui.run_modal_subdialog(launcher_dialog, st) ~= "ok" then
		return
	end
	pcall(function() pyio.save_values(LAUNCHER_STORE, {pick = st.pick}) end)
	st.actions[st.pick][2]()
end

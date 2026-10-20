-- Profile Runs v0.1 (2026-10-18)
-- Straight runs of a fixed cross-section, named so Workshop / Type Automatic rules can fire on them:
--   1. LED channel (aluminium body + diffuser + LED strip) in generic surface / recessed / corner profiles
--   2. Closet rod (round or oval) with end sockets and centre supports
-- Nothing is cut here. A recessed channel is placed as a part named "LED Channel,<profile>" (name pattern editable in the
-- dialog) and the groove is made by the shop's own Workshop operation that fires on that name.
-- Origin: LED channel = start of the run, centre of the mounting face. Closet rod = left face of the opening, rod centre.
-- Profile sizes are GENERIC guesses in mm (see PROFILES) - replace with the shop's real channel.

local HISTORY_KEY = "profile_run_history"

-- cross-sections in mm. u = across the channel (symmetric), v = toward the light; v = 0 is the mounting surface.
-- body: one closed outline. diffuser / strip: {u_low, u_high, v_low, v_high}
local PROFILES = {
	{label = "Surface 17x7", body = {{-8.5,0},{8.5,0},{8.5,7},{7.5,7},{7.5,1},{-7.5,1},{-7.5,7},{-8.5,7}},
		diffuser = {-7.5, 7.5, 6, 7}, strip = {-5, 5, 1, 1.4}},
	{label = "Recessed 17x7", body = {{-8.5,-7},{8.5,-7},{8.5,-0.8},{11,-0.8},{11,0},{7.5,0},{7.5,-6},{-7.5,-6},{-7.5,0},{-11,0},{-11,-0.8},{-8.5,-0.8}},
		diffuser = {-7.5, 7.5, -1, 0}, strip = {-5, 5, -6, -5.6}},
	{label = "Recessed slim 10x5", body = {{-5,-5},{5,-5},{5,-0.8},{6.5,-0.8},{6.5,0},{4.2,0},{4.2,-4.2},{-4.2,-4.2},{-4.2,0},{-6.5,0},{-6.5,-0.8},{-5,-0.8}},
		diffuser = {-4.2, 4.2, -1, 0}, strip = {-3, 3, -4.2, -3.9}},
	{label = "Corner 45deg 16x16", body = {{0,0},{11.31,11.31},{9.9,11.31},{0,1.414},{-9.9,11.31},{-11.31,11.31}},
		diffuser = {-8.9, 8.9, 10.3, 11.31}, strip = {-3, 3, 7, 7.4}},
}

local DEFAULTS_IN = {
	kind = 1, origin = {0, 0, 0}, length = 48, name_pattern = "LED Channel,%s",
	-- LED channel
	profile = 2, axis = 1, direction = 1, diffuser = true, strip = true,
	-- closet rod
	rod_shape = 1, rod_dia = 1.3125, oval_w = 1.625, oval_h = 0.9375, sockets = true, support_rise = 3, support_every = 48,
}
local NAME_DEFAULT = {"LED Channel,%s", "Closet Rod"}

local function length_unit_factor()
	if pytha.get_length_unit() == "in" then return 1 end
	return 25.4
end

local function mm_to_doc(value_mm)
	if pytha.get_length_unit() == "in" then return value_mm / 25.4 end
	return value_mm
end

local function default_data()
	local factor = length_unit_factor()
	local plain = {kind = true, profile = true, axis = true, direction = true, diffuser = true, strip = true, rod_shape = true,
		sockets = true, name_pattern = true}
	local data = {}
	for key, value in pairs(DEFAULTS_IN) do
		if type(value) == "table" then
			data[key] = {value[1] * factor, value[2] * factor, value[3] * factor}
		elseif type(value) == "number" and not plain[key] then
			data[key] = value * factor
		else
			data[key] = value
		end
	end
	return data
end

local function merge_data(from, to)
	for key, value in pairs(from) do
		if to[key] ~= nil and type(to[key]) == type(value) then to[key] = value end
	end
end

local function as_list(result)
	if result == nil then return {} end
	if type(result) == "table" and result[1] ~= nil then return result end
	return {result}
end

local function fit_min(elements, min_x, min_y, min_z)
	local low = {math.huge, math.huge, math.huge}
	for _, element in ipairs(elements) do
		local box = pytha.get_element_bounding_box(element)
		for axis = 1, 3 do low[axis] = math.min(low[axis], box[1][axis], box[2][axis]) end
	end
	local target = {min_x, min_y, min_z}
	local shift = {0, 0, 0}
	for axis = 1, 3 do
		if target[axis] ~= nil then shift[axis] = target[axis] - low[axis] end
	end
	if shift[1] ~= 0 or shift[2] ~= 0 or shift[3] ~= 0 then
		for _, element in ipairs(elements) do pytha.move_element(element, shift) end
	end
end

local function extrude(face, length)
	local made = as_list(pytha.create_profile(face, length))
	pcall(function() pytha.delete_element(face) end)
	return made
end

local function add_block(parts, name, size_x, size_y, size_z, x, y, z)
	local block = pytha.create_block(size_x, size_y, size_z, {x, y, z})
	pytha.set_element_name(block, name)
	table.insert(parts, block)
	return block
end

-- a closed outline given in the cross-section plane, extruded along the run axis (axis 1 = x, 2 = y) from the run start
local function add_run(parts, data, name, outline_ab, length)
	-- outline_ab: list of {a, b} in document units, a = horizontal cross-axis (y for an x run, x for a y run), b = z
	local points = {}
	local ox, oy, oz = data.origin[1], data.origin[2], data.origin[3]
	for _, p in ipairs(outline_ab) do
		if data.axis == 1 then table.insert(points, {ox, oy + p[1], oz + p[2]})
		else table.insert(points, {ox + p[1], oy, oz + p[2]}) end
	end
	local edges = {}
	for _ = 1, #points do table.insert(edges, {}) end
	local face = pytha.create_polygon_ex({{points, edges}}, {0, 0, 0})
	local solids = extrude(face, length)
	if #solids == 0 then error("extrusion failed for " .. name) end
	if data.axis == 1 then fit_min(solids, ox, nil, nil) else fit_min(solids, nil, oy, nil) end
	for _, solid in ipairs(solids) do pytha.set_element_name(solid, name); table.insert(parts, solid) end
end

-- (u, v) in mm -> (a, b) in document units for the chosen light direction
local function map_uv(direction, u, v)
	u, v = mm_to_doc(u), mm_to_doc(v)
	if direction == 1 then return {u, -v}		--light down
	elseif direction == 2 then return {u, v}	--light up
	elseif direction == 3 then return {-v, u}	--light toward the front (-y for an x run, -x for a y run)
	end
	return {v, u}								--light toward the back / right
end

local function rect_outline(direction, box)
	return {map_uv(direction, box[1], box[3]), map_uv(direction, box[2], box[3]), map_uv(direction, box[2], box[4]), map_uv(direction, box[1], box[4])}
end

local function build_led(parts, data)
	local profile = PROFILES[data.profile]
	local outline = {}
	for _, p in ipairs(profile.body) do table.insert(outline, map_uv(data.direction, p[1], p[2])) end
	add_run(parts, data, string.format(data.name_pattern, profile.label), outline, data.length)
	if data.diffuser then add_run(parts, data, "LED Diffuser", rect_outline(data.direction, profile.diffuser), data.length) end
	if data.strip then add_run(parts, data, "LED Strip", rect_outline(data.direction, profile.strip), data.length) end
end

local function ellipse_outline(width, height, centre_y, centre_z)
	local pts = {}
	local steps = 40
	for index = 0, steps - 1 do
		local angle = 2 * math.pi * index / steps
		table.insert(pts, {centre_y + width / 2 * math.cos(angle), centre_z + height / 2 * math.sin(angle)})
	end
	return pts
end

local function build_rod(parts, data)
	local ox, oy, oz = data.origin[1], data.origin[2], data.origin[3]
	local width, height
	if data.rod_shape == 1 then width, height = data.rod_dia, data.rod_dia else width, height = data.oval_w, data.oval_h end
	-- the rod is built along x from the origin: oval's long axis is vertical (as closet rods hang)
	local socket_depth = data.sockets and 0.75 * length_unit_factor() or 0
	local insert = 0.5 * length_unit_factor()
	local rod_start = math.max(0, socket_depth - insert)
	local rod_length = data.length - 2 * rod_start
	local axis_saved = data.axis
	data.axis = 1
	local shape
	if data.rod_shape == 1 then
		shape = ellipse_outline(width, width, 0, 0)
	else
		shape = ellipse_outline(height, width, 0, 0)	--narrow across y, tall in z
	end
	-- run starts at ox + rod_start
	local saved_origin = data.origin
	data.origin = {ox + rod_start, oy, oz}
	add_run(parts, data, (string.format(data.name_pattern, ""):gsub(",%s*$", "")), shape, rod_length)
	data.origin = saved_origin
	data.axis = axis_saved
	local tall = (data.rod_shape == 1) and width or width
	local across = (data.rod_shape == 1) and width or height
	if data.sockets then
		local plate_y, plate_z = across + 0.5 * length_unit_factor(), tall + 0.5 * length_unit_factor()
		add_block(parts, "Rod socket L", socket_depth, plate_y, plate_z, ox, oy - plate_y / 2, oz - plate_z / 2)
		add_block(parts, "Rod socket R", socket_depth, plate_y, plate_z, ox + data.length - socket_depth, oy - plate_y / 2, oz - plate_z / 2)
	end
	local every = math.max(data.support_every, 1e-6)
	local support_count = math.max(0, math.ceil(data.length / every) - 1)
	for index = 1, support_count do
		local x = ox + data.length * index / (support_count + 1)
		local sup_w = 0.75 * length_unit_factor()
		add_block(parts, "Rod support " .. index, sup_w, across, data.support_rise + tall / 2, x - sup_w / 2, oy - across / 2, oz)
	end
end

local function build(data)
	local parts = {}
	if data.kind == 1 then build_led(parts, data) else build_rod(parts, data) end
	return parts
end

local function plain_copy(data)
	local copy = {}
	for key, value in pairs(data) do
		if key ~= "main_group" and key ~= "controls" then
			if type(value) == "table" then
				local inner = {}
				for index, item in ipairs(value) do inner[index] = item end
				copy[key] = inner
			elseif type(value) ~= "function" and type(value) ~= "userdata" then
				copy[key] = value
			end
		end
	end
	return copy
end

local function remove_group(data)
	if data.main_group ~= nil then
		pcall(function() pytha.delete_element(pytha.get_group_members(data.main_group)) end)
		pcall(function() pytha.delete_element(data.main_group) end)
		data.main_group = nil
	end
end

function recreate_run(data)
	remove_group(data)
	local ok, parts = pcall(build, data)
	if not ok then
		pyui.alert(pyloc "Could not build the run:" .. "\n" .. tostring(parts))
		return
	end
	if #parts == 0 then return end
	data.main_group = pytha.create_group(parts)
	pytha.set_element_name(data.main_group, data.kind == 1 and "LED channel run" or "Closet rod")
	pytha.set_element_history(data.main_group, plain_copy(data), HISTORY_KEY)
end

local USED = {
	[1] = {length = true, name_pattern = true, profile = true, axis = true, direction = true, diffuser = true, strip = true},
	[2] = {length = true, name_pattern = true, rod_shape = true, rod_dia = true, oval_w = true, oval_h = true, sockets = true, support_rise = true, support_every = true},
}

local function run_dialog(dialog, data)
	dialog:set_window_title(pyloc "Profile Runs")
	local controls = {}
	data.controls = controls
	local function refresh() recreate_run(data) end
	local function update_enabled()
		local used = USED[data.kind] or {}
		for key, pair in pairs(controls) do
			if used[key] == true then
				if pair.label then pair.label:enable_control() end
				pair.box:enable_control()
			else
				if pair.label then pair.label:disable_control() end
				pair.box:disable_control()
			end
		end
	end
	local function length_row(col, key, text)
		local label = dialog:create_label(col, text)
		local box = dialog:create_text_box(col + 1, pyui.format_length(data[key]))
		box:set_on_change_handler(function(typed)
			local value = pyui.parse_length(typed)
			if value ~= nil and value >= 0 then data[key] = value; refresh() end
		end)
		controls[key] = {label = label, box = box}
	end

	local pick_origin = dialog:create_button(1, pyloc "Pick origin")
	local kind_label = dialog:create_label(3, pyloc "Type")
	local kind_list = dialog:create_drop_list(4)
	kind_list:insert_control_item(pyloc "LED channel")
	kind_list:insert_control_item(pyloc "Closet rod")
	kind_list:set_control_selection(data.kind)

	length_row(1, "length", pyloc "Run length / opening width")
	local pattern_label = dialog:create_label(3, pyloc "Part name (%s = profile)")
	local pattern_box = dialog:create_text_box(4, data.name_pattern)
	pattern_box:set_on_change_handler(function(typed)
		if typed ~= nil and typed ~= "" then data.name_pattern = typed; refresh() end
	end)
	controls.name_pattern = {label = pattern_label, box = pattern_box}

	local profile_label = dialog:create_label(1, pyloc "Profile")
	local profile_list = dialog:create_drop_list(2)
	profile_list:insert_control_item(pyloc "Surface 17x7")
	profile_list:insert_control_item(pyloc "Recessed 17x7")
	profile_list:insert_control_item(pyloc "Recessed slim 10x5")
	profile_list:insert_control_item(pyloc "Corner 45deg 16x16")
	profile_list:set_control_selection(data.profile)
	controls.profile = {label = profile_label, box = profile_list}
	local axis_label = dialog:create_label(3, pyloc "Run along")
	local axis_list = dialog:create_drop_list(4)
	axis_list:insert_control_item(pyloc "X (left-right)")
	axis_list:insert_control_item(pyloc "Y (front-back)")
	axis_list:set_control_selection(data.axis)
	controls.axis = {label = axis_label, box = axis_list}
	local direction_label = dialog:create_label(1, pyloc "Light toward")
	local direction_list = dialog:create_drop_list(2)
	direction_list:insert_control_item(pyloc "Down")
	direction_list:insert_control_item(pyloc "Up")
	direction_list:insert_control_item(pyloc "Front / left (-)")
	direction_list:insert_control_item(pyloc "Back / right (+)")
	direction_list:set_control_selection(data.direction)
	controls.direction = {label = direction_label, box = direction_list}
	local diffuser_check = dialog:create_check_box({3, 4}, pyloc "Diffuser part")
	diffuser_check:set_control_checked(data.diffuser)
	controls.diffuser = {box = diffuser_check}
	local strip_check = dialog:create_check_box({1, 2}, pyloc "LED strip part")
	strip_check:set_control_checked(data.strip)
	controls.strip = {box = strip_check}

	local shape_label = dialog:create_label(3, pyloc "Rod shape")
	local shape_list = dialog:create_drop_list(4)
	shape_list:insert_control_item(pyloc "Round")
	shape_list:insert_control_item(pyloc "Oval")
	shape_list:set_control_selection(data.rod_shape)
	controls.rod_shape = {label = shape_label, box = shape_list}
	length_row(1, "rod_dia", pyloc "Round diameter")
	length_row(3, "oval_w", pyloc "Oval height (tall)")
	length_row(1, "oval_h", pyloc "Oval width (across)")
	length_row(3, "support_rise", pyloc "Support height above rod")
	length_row(1, "support_every", pyloc "Support every")
	local sockets_check = dialog:create_check_box({3, 4}, pyloc "End sockets")
	sockets_check:set_control_checked(data.sockets)
	controls.sockets = {box = sockets_check}

	dialog:create_ok_button(3)
	dialog:create_cancel_button(4)

	pick_origin:set_on_click_handler(function()
		pick_origin:disable_control()
		local picked = pyux.select_coordinate()
		if picked ~= nil then data.origin = picked end
		pick_origin:enable_control()
		refresh()
	end)
	kind_list:set_on_change_handler(function(text, new_index)
		data.kind = new_index
		data.name_pattern = NAME_DEFAULT[new_index]
		pattern_box:set_control_text(data.name_pattern)
		update_enabled()
		refresh()
	end)
	profile_list:set_on_change_handler(function(text, new_index) data.profile = new_index; refresh() end)
	axis_list:set_on_change_handler(function(text, new_index) data.axis = new_index; refresh() end)
	direction_list:set_on_change_handler(function(text, new_index) data.direction = new_index; refresh() end)
	shape_list:set_on_change_handler(function(text, new_index) data.rod_shape = new_index; refresh() end)
	diffuser_check:set_on_click_handler(function(state) data.diffuser = state; refresh() end)
	strip_check:set_on_click_handler(function(state) data.strip = state; refresh() end)
	sockets_check:set_on_click_handler(function(state) data.sockets = state; refresh() end)
	update_enabled()
end

function profile_runs()
	local data = default_data()
	local loaded = pyio.load_values("profile_run_settings")
	if type(loaded) == "table" then merge_data(loaded, data) end
	data.main_group = nil
	recreate_run(data)
	local result = pyui.run_modal_dialog(run_dialog, data)
	if result ~= nil and result ~= "ok" then remove_group(data); return end
	local saved = plain_copy(data)
	saved.origin = nil
	pyio.save_values("profile_run_settings", saved)
end

function edit_profile_run()
	local picked = pyux.select_part(false, pyloc "Select the run to edit")
	if picked == nil or picked[1] == nil then return end
	local group = picked[1]
	local history = nil
	while group ~= nil do
		history = pytha.get_element_history(group, HISTORY_KEY)
		if history ~= nil then break end
		group = pytha.get_element_parent_group(group)
	end
	if history == nil then
		pyui.alert(pyloc "That is not a Profile Runs object (no stored settings found).")
		return
	end
	local function restore()
		local data = default_data(); merge_data(history, data)
		if type(history.origin) == "table" then data.origin = {history.origin[1], history.origin[2], history.origin[3]} end
		return data
	end
	local data = restore()
	data.main_group = group
	recreate_run(data)
	local result = pyui.run_modal_dialog(run_dialog, data)
	if result ~= nil and result ~= "ok" then
		remove_group(data)
		recreate_run(restore())
	end
end

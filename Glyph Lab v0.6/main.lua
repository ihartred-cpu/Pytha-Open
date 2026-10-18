-- Glyph Lab v0.6 (2026-10-15) - a TEST plugin: builds a smiley and a warning "!" sign several ways and reports,
-- call by call, what this PYTHA install accepts. Nothing is assumed to be a V27 wall until the report says so:
-- every call runs inside pcall and the exact error text is kept.
-- Layout of the result: one top-level group "Glyph Lab" with every variant side by side along +x (front view, x-z plane).
-- Report: shown in an alert and, if the scratch folder is writable, saved as glyph_lab_report.txt (path in the alert).

local GROUP_NAME = "Glyph Lab"
local STEP_MM = 160		--spacing between variants

local DEFAULTS = {size_mm = 100, thick_mm = 6, pen_body = 0, pen_feature = 0, sheet_tests = false, keep_sheet = true}

local function to_doc(value_mm)
	if pytha.get_length_unit() == "in" then return value_mm / 25.4 end
	return value_mm
end

local function mm_to_doc(value_mm) return to_doc(value_mm) end

local results = {}		--{name, succeeded, detail}
local top_level_items = {}		--every top-level thing to put in the final group

local function record(name, succeeded, detail)
	table.insert(results, {name, succeeded, tostring(detail or "")})
end

--run fn; keep success/error text; returns ok, value
local function try(name, function_to_run)
	local call_ok, value_or_error = pcall(function_to_run)
	if call_ok then
		record(name, true, "ok")
	else
		record(name, false, value_or_error)
	end
	return call_ok, value_or_error
end

local function first(handle)
	if type(handle) == "table" then return handle[1] end
	return handle
end

local function size_of(handle)
	local call_ok, box = pcall(function() return pytha.get_element_bounding_box(first(handle)) end)
	if call_ok and type(box) == "table" and box[1] and box[2] then
		return string.format("%.1f x %.1f x %.1f mm", math.abs(box[2][1]-box[1][1]) * (pytha.get_length_unit() == "in" and 25.4 or 1),
			math.abs(box[2][2]-box[1][2]) * (pytha.get_length_unit() == "in" and 25.4 or 1),
			math.abs(box[2][3]-box[1][3]) * (pytha.get_length_unit() == "in" and 25.4 or 1))
	end
	return "no bounding box"
end

local function paint(handle, pen)
	if handle ~= nil and pen and pen > 0 then
		pcall(function() pytha.set_element_pen(first(handle), pen) end)
	end
end

-- flat geometry is drawn in local (u,v) = the front view (x right, z up), w toward -y, so "extrude" goes into the wall
local function in_front_plane(offset_x_mm, build_function)
	local token = pytha.push_local_coordinates({mm_to_doc(offset_x_mm), 0, 0}, {u_axis = {1, 0, 0}, v_axis = {0, 0, 1}, w_axis = {0, -1, 0}})
	local call_ok, first_result, second_result = pcall(build_function)
	pytha.pop_local_coordinates(token)
	if not call_ok then error(first_result, 0) end
	return first_result, second_result
end

-- loop helpers (all mm, converted here). A full circle = two 180 deg arcs (the wiki's own pattern).
local function circle_loop(centre_x, centre_y, radius, reversed)
	if reversed then
		return {{ {mm_to_doc(centre_x + radius), mm_to_doc(centre_y)}, {mm_to_doc(centre_x - radius), mm_to_doc(centre_y)} }, { {angle = -180, segments = 24}, {angle = -180, segments = 24} }}
	end
	return {{ {mm_to_doc(centre_x - radius), mm_to_doc(centre_y)}, {mm_to_doc(centre_x + radius), mm_to_doc(centre_y)} }, { {angle = 180, segments = 24}, {angle = 180, segments = 24} }}
end

-- smiley loops for size s (mm): face circle, two eyes, crescent mouth
local function smiley_loops(size, reversed)
	local radius = size / 2
	local eye = radius * 0.12
	local outer = circle_loop(0, 0, radius)
	local left_eye = circle_loop(-radius * 0.36, radius * 0.28, eye, reversed)
	local right_eye = circle_loop(radius * 0.36, radius * 0.28, eye, reversed)
	local mouth = {
		{ {mm_to_doc(-radius * 0.58), mm_to_doc(-radius * 0.12)}, {mm_to_doc(radius * 0.58), mm_to_doc(-radius * 0.12)} },
		{ {angle = 150, segments = 24}, {angle = -85, segments = 24} },	--deep arc out, shallower arc back = crescent
	}
	if reversed then
		mouth[2] = { {angle = 85, segments = 24}, {angle = -150, segments = 24} }
	end
	return outer, left_eye, right_eye, mouth
end

-- warning sign loops for size s (mm): triangle, bar, dot
local function warning_loops(size, reversed)
	local width, height = size, size * 0.866
	local triangle = {{ {mm_to_doc(-width / 2), 0}, {mm_to_doc(width / 2), 0}, {mm_to_doc(0), mm_to_doc(height)} }}
	local bar = {{ {mm_to_doc(-size * 0.05), mm_to_doc(height * 0.30)}, {mm_to_doc(size * 0.05), mm_to_doc(height * 0.30)}, {mm_to_doc(size * 0.035), mm_to_doc(height * 0.70)}, {mm_to_doc(-size * 0.035), mm_to_doc(height * 0.70)} }}
	if reversed then
		bar = {{ {mm_to_doc(-size * 0.05), mm_to_doc(height * 0.30)}, {mm_to_doc(-size * 0.035), mm_to_doc(height * 0.70)}, {mm_to_doc(size * 0.035), mm_to_doc(height * 0.70)}, {mm_to_doc(size * 0.05), mm_to_doc(height * 0.30)} }}
	end
	local dot = circle_loop(0, height * 0.14, size * 0.06, reversed)
	return triangle, bar, dot
end

local function extrude_face(face, thick_mm)
	local profile_result = pytha.create_profile(first(face), mm_to_doc(thick_mm))
	pcall(function() pytha.delete_element(first(face)) end)	--create_profile keeps its base face
	return first(profile_result)
end

----------------------------------------------------------------------------------------------------------------
-- tests
----------------------------------------------------------------------------------------------------------------
local function run(settings)
	local offset_x = 0
	local function next_offset_x() local current_x = offset_x; offset_x = offset_x + STEP_MM; return current_x end

	-- A. text: the "baseline" V26 call (the one Group Numbering 1.4 already relies on)
	local call_ok, handle
	call_ok, handle = try("T1 create_text_3d(text,height,thickness) - V26 baseline", function()
		return in_front_plane(next_offset_x(), function() return pytha.create_text_3d("!", mm_to_doc(settings.size_mm), mm_to_doc(settings.thick_mm)) end)
	end)
	if call_ok then paint(handle, settings.pen_feature); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- B. text with origin + options (font/bold/orientation) - wiki lists these; does V26 take them?
	call_ok, handle = try("T2 create_text_3d with origin + options (Arial, bold, centre) - accepted, effect not proven", function()
		return in_front_plane(next_offset_x(), function()
			return pytha.create_text_3d("!", mm_to_doc(settings.size_mm), mm_to_doc(settings.thick_mm), {0, 0, 0}, {font = "Arial", bold = true, orientation = "center"})
		end)
	end)
	if call_ok then paint(handle, settings.pen_feature); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- C. emoji glyph through the text path (default font, then an emoji font through the options form)
	call_ok, handle = try("T3 create_text_3d with the emoji character (default font)", function()
		return in_front_plane(next_offset_x(), function() return pytha.create_text_3d("\u{1F642}", mm_to_doc(settings.size_mm), mm_to_doc(settings.thick_mm)) end)
	end)
	if call_ok then
		paint(handle, settings.pen_feature); table.insert(top_level_items, handle)
		local size_text = size_of(handle)
		record("   size (a tiny or empty box means the font has no emoji glyph)", true, size_text)
	end
	call_ok, handle = try("T4 create_text_3d with emoji + font 'Segoe UI Emoji' (options form)", function()
		return in_front_plane(next_offset_x(), function()
			return pytha.create_text_3d("\u{1F642}", mm_to_doc(settings.size_mm), mm_to_doc(settings.thick_mm), {0, 0, 0}, {font = "Segoe UI Emoji"})
		end)
	end)
	if call_ok then paint(handle, settings.pen_feature); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- D. text as pure linework (edges only, no volume)
	call_ok, handle = try("T5 create_text_engraving - letters as edge curves", function()
		return in_front_plane(next_offset_x(), function() return pytha.create_text_engraving("!", mm_to_doc(settings.size_mm)) end)
	end)
	if call_ok then paint(handle, settings.pen_feature); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end
	call_ok, handle = try("T6 create_text_engraving with options (open contours)", function()
		return in_front_plane(next_offset_x(), function() return pytha.create_text_engraving("!", mm_to_doc(settings.size_mm), {0, 0, 0}, {open = true, font = "Arial"}) end)
	end)
	if call_ok then paint(handle, settings.pen_feature); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- D2. the emoji as pure linework: contours only, no volume (could be turned into faces/extruded at different heights)
	call_ok, handle = try("T5b create_text_engraving with the emoji character (contours only)", function()
		return in_front_plane(next_offset_x(), function() return pytha.create_text_engraving("\u{1F642}", mm_to_doc(settings.size_mm)) end)
	end)
	if call_ok then paint(handle, settings.pen_feature); table.insert(top_level_items, handle); record("   size (0 thick = edges only; compare the face detail by eye with T3)", true, size_of(handle)) end
	call_ok, handle = try("T5c create_text_engraving emoji, font 'Segoe UI Emoji', open contours", function()
		return in_front_plane(next_offset_x(), function() return pytha.create_text_engraving("\u{1F642}", mm_to_doc(settings.size_mm), {0, 0, 0}, {font = "Segoe UI Emoji", open = true}) end)
	end)
	if call_ok then paint(handle, settings.pen_feature); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- E. smiley, variant 1: ONE face with holes (eyes + mouth are real cut-outs), extruded
	call_ok, handle = try("T7 smiley as one polygon_ex with holes + create_profile", function()
		return in_front_plane(next_offset_x(), function()
			local outer, left_eye, right_eye, mouth = smiley_loops(settings.size_mm)
			local face = pytha.create_polygon_ex({outer, left_eye, right_eye, mouth})
			return extrude_face(face, settings.thick_mm)
		end)
	end)
	if call_ok then paint(handle, settings.pen_body); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- E2. diagnose the missing holes: the flat face alone (look at it before any extrusion), then holes wound the other way
	call_ok, handle = try("T7b smiley FACE ONLY (polygon_ex, no extrusion) - holes visible?", function()
		return in_front_plane(next_offset_x(), function()
			local outer, left_eye, right_eye, mouth = smiley_loops(settings.size_mm)
			return pytha.create_polygon_ex({outer, left_eye, right_eye, mouth})
		end)
	end)
	if call_ok then table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end
	call_ok, handle = try("T7c smiley polygon_ex, holes wound opposite, extruded", function()
		return in_front_plane(next_offset_x(), function()
			local outer = smiley_loops(settings.size_mm)
			local _, left_eye, right_eye, mouth = smiley_loops(settings.size_mm, true)
			return extrude_face(pytha.create_polygon_ex({outer, left_eye, right_eye, mouth}), settings.thick_mm)
		end)
	end)
	if call_ok then paint(handle, settings.pen_body); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- F. smiley, variant 2: layered - disc, plus separate eye/mouth parts sitting on it (different colours possible)
	call_ok, handle = try("T8 smiley layered: disc + raised eyes + raised mouth (3 pens possible)", function()
		return in_front_plane(next_offset_x(), function()
			local outer, left_eye, right_eye, mouth = smiley_loops(settings.size_mm)
			local parts = {}
			local disc = extrude_face(pytha.create_polygon_ex({outer}), settings.thick_mm)
			paint(disc, settings.pen_body); table.insert(parts, disc)
			local token = pytha.push_local_coordinates({0, 0, mm_to_doc(settings.thick_mm)}, {})	--raise features: w points to -y (toward the viewer), so on top of the disc is +w
			local features_ok, error_message = pcall(function()
				for _, loop in ipairs({left_eye, right_eye, mouth}) do
					local feature = extrude_face(pytha.create_polygon_ex({loop}), settings.thick_mm * 0.5)
					paint(feature, settings.pen_feature); table.insert(parts, feature)
				end
			end)
			pytha.pop_local_coordinates(token)
			if not features_ok then error(error_message, 0) end
			return pytha.create_group(parts, {name = "Smiley layered"})
		end)
	end)
	if call_ok then table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- G. smiley, variant 3: solid disc minus separate eye/mouth solids via boolean difference
	call_ok, handle = try("T9 smiley via boole_part_difference (disc minus eyes/mouth)", function()
		return in_front_plane(next_offset_x(), function()
			local outer, left_eye, right_eye, mouth = smiley_loops(settings.size_mm)
			local disc = extrude_face(pytha.create_polygon_ex({outer}), settings.thick_mm)
			local cutters = {}
			for _, loop in ipairs({left_eye, right_eye, mouth}) do
				table.insert(cutters, extrude_face(pytha.create_polygon_ex({loop}), settings.thick_mm))
			end
			return pytha.boole_part_difference(disc, cutters)
		end)
	end)
	if call_ok then paint(handle, settings.pen_body); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- H. smiley, variant 4: primitives only (circle + create_ring as a rim) - ring is listed as V27 on the wiki
	call_ok, handle = try("T10 create_ring as a rim (wiki says V27)", function()
		return in_front_plane(next_offset_x(), function()
			return pytha.create_ring(mm_to_doc(settings.size_mm / 2), mm_to_doc(settings.thick_mm / 2))
		end)
	end)
	if call_ok then paint(handle, settings.pen_body); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- I. smiley, variant 5: pure linework (closed polylines with arcs) - an outline-only icon for plot sheets/2D
	call_ok, handle = try("T11 smiley as linework only (polyline_ex loops)", function()
		return in_front_plane(next_offset_x(), function()
			local radius = settings.size_mm / 2
			local parts = {}
			local function loop(loop_points) return pytha.create_polyline_ex("closed", loop_points[1], loop_points[2]) end
			local outer, left_eye, right_eye, mouth = smiley_loops(settings.size_mm)
			for _, loop_points in ipairs({outer, left_eye, right_eye, mouth}) do table.insert(parts, loop(loop_points)) end
			return pytha.create_group(parts, {name = "Smiley lines"})
		end)
	end)
	if call_ok then paint(handle, settings.pen_feature); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- J. warning sign, variant 1: triangle with the exclamation cut out, extruded
	call_ok, handle = try("T12 warning triangle with '!' cut-outs (polygon_ex + profile)", function()
		return in_front_plane(next_offset_x(), function()
			local triangle, bar, dot = warning_loops(settings.size_mm)
			local face = pytha.create_polygon_ex({triangle, bar, dot})
			return extrude_face(face, settings.thick_mm)
		end)
	end)
	if call_ok then paint(handle, settings.pen_body); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	call_ok, handle = try("T12b warning polygon_ex, holes wound opposite, extruded", function()
		return in_front_plane(next_offset_x(), function()
			local triangle = warning_loops(settings.size_mm)
			local _, bar, dot = warning_loops(settings.size_mm, true)
			return extrude_face(pytha.create_polygon_ex({triangle, bar, dot}), settings.thick_mm)
		end)
	end)
	if call_ok then paint(handle, settings.pen_body); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end
	call_ok, handle = try("T12c warning via boole_part_difference (triangle minus bar and dot)", function()
		return in_front_plane(next_offset_x(), function()
			local triangle, bar, dot = warning_loops(settings.size_mm)
			local base = extrude_face(pytha.create_polygon_ex({triangle}), settings.thick_mm)
			local cutters = {}
			for _, loop in ipairs({bar, dot}) do
				table.insert(cutters, extrude_face(pytha.create_polygon_ex({loop}), settings.thick_mm))
			end
			return pytha.boole_part_difference(base, cutters)
		end)
	end)
	if call_ok then paint(handle, settings.pen_body); table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

	-- K. warning sign, variant 2: layered triangle + raised "!" bar and dot in a second pen
	call_ok, handle = try("T13 warning layered: triangle + raised '!' (2 pens possible)", function()
		return in_front_plane(next_offset_x(), function()
			local triangle, bar, dot = warning_loops(settings.size_mm)
			local parts = {}
			local base = extrude_face(pytha.create_polygon_ex({triangle}), settings.thick_mm)
			paint(base, settings.pen_body); table.insert(parts, base)
			local token = pytha.push_local_coordinates({0, 0, mm_to_doc(settings.thick_mm)}, {})
			local features_ok, error_message = pcall(function()
				for _, loop in ipairs({bar, dot}) do
					local feature = extrude_face(pytha.create_polygon_ex({loop}), settings.thick_mm * 0.5)
					paint(feature, settings.pen_feature); table.insert(parts, feature)
				end
			end)
			pytha.pop_local_coordinates(token)
			if not features_ok then error(error_message, 0) end
			return pytha.create_group(parts, {name = "Warning layered"})
		end)
	end)
	if call_ok then table.insert(top_level_items, handle); record("   size", true, size_of(handle)) end

end

----------------------------------------------------------------------------------------------------------------
-- dialog + report
----------------------------------------------------------------------------------------------------------------
local function dialog_fn(dialog, settings)
	dialog:set_window_title(pyloc "Glyph Lab 0.6")
	dialog:create_standalone_label({1, 2}, pyloc "Builds a smiley and a warning sign several ways and reports what this PYTHA accepts.")
	dialog:create_label(1, pyloc "Glyph size (mm)")
	local size = dialog:create_text_box(2, pyui.format_number(settings.size_mm))
	size:set_on_change_handler(function(text)
		local typed_number = pyui.parse_number(text)
		if typed_number ~= nil and typed_number >= 10 and typed_number <= 1000 then settings.size_mm = typed_number end
	end)
	dialog:create_label(1, pyloc "Thickness (mm)")
	local thick = dialog:create_text_box(2, pyui.format_number(settings.thick_mm))
	thick:set_on_change_handler(function(text)
		local typed_number = pyui.parse_number(text)
		if typed_number ~= nil and typed_number >= 0.5 and typed_number <= 200 then settings.thick_mm = typed_number end
	end)
	dialog:create_label(1, pyloc "Body pen (0 = leave)")
	local body_pen_box = dialog:create_text_box(2, pyui.format_number(settings.pen_body))
	body_pen_box:set_on_change_handler(function(text)
		local typed_number = pyui.parse_number(text)
		if typed_number ~= nil and typed_number >= 0 and typed_number <= 256 then settings.pen_body = math.floor(typed_number) end
	end)
	dialog:create_label(1, pyloc "Feature pen (0 = leave)")
	local feature_pen_box = dialog:create_text_box(2, pyui.format_number(settings.pen_feature))
	feature_pen_box:set_on_change_handler(function(text)
		local typed_number = pyui.parse_number(text)
		if typed_number ~= nil and typed_number >= 0 and typed_number <= 256 then settings.pen_feature = math.floor(typed_number) end
	end)
	local sheet_tests_check = dialog:create_check_box({1, 2}, pyloc "Also test plot-sheet calls (makes a sheet 'Glyph Lab sheet')")
	sheet_tests_check:set_control_checked(settings.sheet_tests)
	sheet_tests_check:set_on_click_handler(function(state) settings.sheet_tests = state end)
	local keep_sheet_check = dialog:create_check_box({1, 2}, pyloc "Keep that sheet afterwards (otherwise it is deleted)")
	keep_sheet_check:set_control_checked(settings.keep_sheet)
	keep_sheet_check:set_on_click_handler(function(state) settings.keep_sheet = state end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

local function sheet_tests(settings, group)
	local create_ok, sheet = try("S1 pyplot.create_sheet('Glyph Lab sheet') - wiki says V26", function()
		return pyplot.create_sheet("Glyph Lab sheet")
	end)
	if not create_ok then return end
	--the sheet's length unit is not documented: 0.3 sent mm numbers to an inch Letter sheet and the sheet looked empty.
	--So every sheet call is made twice, once with mm numbers (A) and once with numbers in the document unit (B), and the
	--scale is derived from the group's real width so the view fits the page either way.
	local group_width_doc = nil
	if group ~= nil then
		local box_ok, box = pcall(function() return pytha.get_element_bounding_box(group) end)
		if box_ok and type(box) == "table" and box[1] and box[2] then group_width_doc = math.abs(box[2][1] - box[1][1]) end
	end
	record("   group width in document units", group_width_doc ~= nil, group_width_doc and string.format("%.2f %s", group_width_doc, pytha.get_length_unit()) or "unknown")
	--0.5 result (by eye): detail POSITION = centre of the view, in document units (inches here); text SIZE is mm;
	--view_min/view_max clip with NO scale placed and fitted the view; the explicit-scale calls (C1/C2) showed nothing.
	--0.6 turns that into a helper, place_view(), and tries a three-view layout with labels and a title block.
	local function to_doc_units(value_mm) return to_doc(value_mm) end
	local group_box
	if group ~= nil then
		local candidate_ok, candidate_box = pcall(function() return pytha.get_element_bounding_box(group) end)
		if candidate_ok and type(candidate_box) == "table" then group_box = candidate_box end
	end
	if not group_box then record("S2 bounding box for the group", false, "unavailable - views skipped"); return end
	local low, high = group_box[1], group_box[2]
	local function span(view_index) return math.abs(high[view_index] - low[view_index]) end
	--axes of each view: which model axes are the view's horizontal / vertical
	local VIEWS = {
		{name = "xz", horizontal_axis = 1, vertical_axis = 3, label = "FRONT"},
		{name = "xy", horizontal_axis = 1, vertical_axis = 2, label = "TOP"},
		{name = "yz", horizontal_axis = 2, vertical_axis = 3, label = "SIDE"},
	}
	--place_view: fits the clipped view into a box of max_width x max_height (document units), centred at (centre_x, centre_y)
	local function place_view(sheet_handle, group_handle, view_spec, centre_x, centre_y, max_width, max_height)
		local width, height = span(view_spec.horizontal_axis), span(view_spec.vertical_axis)
		if width <= 0 or height <= 0 then return nil, "zero extent" end
		local fit_factor = math.min(max_width / width, max_height / height)
		return pyplot.insert_detail(sheet_handle, {
			view = view_spec.name, position = {centre_x, centre_y}, size = {width * fit_factor, height * fit_factor},
			view_min = {low[view_spec.horizontal_axis], low[view_spec.vertical_axis]}, view_max = {high[view_spec.horizontal_axis], high[view_spec.vertical_axis]},
		}, {group_handle})
	end
	--layout in inches on a Letter landscape sheet (11 x 8.5), frame about 0.4 in in
	local cols = {{2.8, 6.4}, {8.2, 6.4}, {2.8, 3.0}}
	for view_index, view_spec in ipairs(VIEWS) do
		local column = cols[view_index]
		try("L" .. view_index .. " place_view " .. view_spec.name .. " (" .. view_spec.label .. ") centred at (" .. column[1] .. ", " .. column[2] .. ") in, via view_min/view_max", function()
			return place_view(sheet, group, view_spec, to_doc_units(column[1] * 25.4), to_doc_units(column[2] * 25.4), to_doc_units(4.6 * 25.4), to_doc_units(1.8 * 25.4))
		end)
		try("L" .. view_index .. "t label " .. view_spec.label, function()
			return pyplot.insert_text(sheet, view_spec.label .. " VIEW", {size = 4, position = {to_doc_units(column[1] * 25.4 - 0.5 * 25.4), to_doc_units((column[2] - 1.2) * 25.4)}, bold = true, font = "Arial"})
		end)
	end
	--title block: name, number, date, all as plain sheet text
	try("L4 title block texts", function()
		pyplot.insert_text(sheet, "GLYPH LAB - ELEVATIONS", {size = 6, position = {to_doc_units(0.6 * 25.4), to_doc_units(1.1 * 25.4)}, bold = true, font = "Arial"})
		pyplot.insert_text(sheet, "A-101", {size = 9, position = {to_doc_units(8.6 * 25.4), to_doc_units(1.1 * 25.4)}, bold = true, font = "Arial"})
		pyplot.insert_text(sheet, "Pytha V26, compiled 2026-07-20 14:19:45", {size = 3, position = {to_doc_units(0.6 * 25.4), to_doc_units(0.75 * 25.4)}, font = "Arial"})
	end)
	--pydim: the 0.3 run showed the whole namespace is missing on this build ("global 'pydim' is nil"). Keep the probe, but say so plainly.
	if type(pydim) ~= "table" then
		record("S5 pydim.create_text", false, "the pydim namespace does not exist on this build (global pydim is nil) - a real V27 wall")
	else
		local dim_ok, dim_text = try("S5 pydim.create_text", function()
			return pydim.create_text("ELEV A", {{0, 0, 0}}, {view = "xz", style = {size = 6}})
		end)
		if dim_ok and dim_text ~= nil then pcall(function() pytha.delete_element(dim_text) end) end
	end
	if not settings.keep_sheet then
		try("S6 pyplot.delete_sheet", function() pyplot.delete_sheet(sheet) end)
	end
end

function glyph_lab()
	local settings = {}
	for key, value in pairs(DEFAULTS) do settings[key] = value end
	local ok_load, saved = pcall(function() return pyio.load_values("glyph_lab_settings") end)
	if ok_load and type(saved) == "table" then
		for key, value in pairs(saved) do
			if DEFAULTS[key] ~= nil and type(value) == type(DEFAULTS[key]) then settings[key] = value end
		end
	end
	if pyui.run_modal_subdialog(dialog_fn, settings) ~= "ok" then return end
	pcall(function() pyio.save_values("glyph_lab_settings", settings) end)

	results, top_level_items = {}, {}
	-- a re-run replaces the old test group
	local old_groups = {}		--collect first: deleting while enumerate_groups is still looping can skip groups
	for candidate in pytha.enumerate_groups() do
		local name_ok, group_name_value = pcall(function() return pytha.get_element_attribute(candidate, 3) end)
		if name_ok and tostring(group_name_value) == GROUP_NAME and pytha.get_element_parent_group(candidate) == nil then
			table.insert(old_groups, candidate)
		end
	end
	for _, old_group in ipairs(old_groups) do
		pcall(function() pytha.delete_element(old_group) end)
	end
	local run_ok, run_error = pcall(run, settings)
	if not run_ok then record("run aborted", false, run_error) end
	local group
	if #top_level_items > 0 then
		local flat = {}
		for _, item in ipairs(top_level_items) do table.insert(flat, first(item)) end
		local group_ok, created_group = pcall(function() return pytha.create_group(flat, {name = GROUP_NAME}) end)
		if group_ok then group = created_group end
	end
	if settings.sheet_tests then
		local sheet_ok, sheet_error = pcall(sheet_tests, settings, group)
		if not sheet_ok then record("sheet tests aborted", false, sheet_error) end
	end

	local lines, passed, failed = {"Glyph Lab 0.6 report", ""}, 0, 0
	for _, result_row in ipairs(results) do
		if result_row[2] then passed = passed + 1 else failed = failed + 1 end
		table.insert(lines, (result_row[2] and "[ok]   " or "[FAIL] ") .. result_row[1] .. (result_row[3] ~= "ok" and result_row[3] ~= "" and ("  ->  " .. result_row[3]) or ""))
	end
	table.insert(lines, "")
	table.insert(lines, passed .. " ok, " .. failed .. " failed. Variants are in the group '" .. GROUP_NAME .. "' (front view, left to right).\nNot tested: saving a glyph as a .pyo library element from Lua (no such call seen in the wiki index) - do it by hand.")
	local text = table.concat(lines, "\n")
	local saved_to = ""
	local write_ok = pcall(function()
		pyio.write_lines(pyio.get_scratch_folder_path("glyph_lab_report.txt"), lines)
	end)
	if write_ok then saved_to = "\n\nReport also saved as glyph_lab_report.txt in the plugin scratch folder." end
	pyui.alert(text .. saved_to)
end

-- Glyph Lab v0.6 (2026-10-15) - a TEST plugin: builds a smiley and a warning "!" sign several ways and reports,
-- call by call, what this PYTHA install accepts. Nothing is assumed to be a V27 wall until the report says so:
-- every call runs inside pcall and the exact error text is kept.
-- Layout of the result: one top-level group "Glyph Lab" with every variant side by side along +x (front view, x-z plane).
-- Report: shown in an alert and, if the scratch folder is writable, saved as glyph_lab_report.txt (path in the alert).

local GROUP_NAME = "Glyph Lab"
local STEP_MM = 160		--spacing between variants

local DEFAULTS = {size_mm = 100, thick_mm = 6, pen_body = 0, pen_feature = 0, sheet_tests = false, keep_sheet = true}

local function to_doc(v_mm)
	if pytha.get_length_unit() == "in" then return v_mm / 25.4 end
	return v_mm
end

local function mm(v) return to_doc(v) end

local results = {}		--{name, ok, detail}
local made = {}		--every top-level thing to put in the final group

local function record(name, ok, detail)
	table.insert(results, {name, ok, tostring(detail or "")})
end

--run fn; keep success/error text; returns ok, value
local function try(name, fn)
	local ok, v = pcall(fn)
	if ok then
		record(name, true, "ok")
	else
		record(name, false, v)
	end
	return ok, v
end

local function first(h)
	if type(h) == "table" then return h[1] end
	return h
end

local function size_of(h)
	local ok, bb = pcall(function() return pytha.get_element_bounding_box(first(h)) end)
	if ok and type(bb) == "table" and bb[1] and bb[2] then
		return string.format("%.1f x %.1f x %.1f mm", math.abs(bb[2][1]-bb[1][1]) * (pytha.get_length_unit() == "in" and 25.4 or 1),
			math.abs(bb[2][2]-bb[1][2]) * (pytha.get_length_unit() == "in" and 25.4 or 1),
			math.abs(bb[2][3]-bb[1][3]) * (pytha.get_length_unit() == "in" and 25.4 or 1))
	end
	return "no bounding box"
end

local function paint(h, pen)
	if h ~= nil and pen and pen > 0 then
		pcall(function() pytha.set_element_pen(first(h), pen) end)
	end
end

-- flat geometry is drawn in local (u,v) = the front view (x right, z up), w toward -y, so "extrude" goes into the wall
local function in_front_plane(x, fn)
	local token = pytha.push_local_coordinates({mm(x), 0, 0}, {u_axis = {1, 0, 0}, v_axis = {0, 0, 1}, w_axis = {0, -1, 0}})
	local ok, a, b = pcall(fn)
	pytha.pop_local_coordinates(token)
	if not ok then error(a, 0) end
	return a, b
end

-- loop helpers (all mm, converted here). A full circle = two 180 deg arcs (the wiki's own pattern).
local function circle_loop(cx, cy, r, rev)
	if rev then
		return {{ {mm(cx + r), mm(cy)}, {mm(cx - r), mm(cy)} }, { {angle = -180, segments = 24}, {angle = -180, segments = 24} }}
	end
	return {{ {mm(cx - r), mm(cy)}, {mm(cx + r), mm(cy)} }, { {angle = 180, segments = 24}, {angle = 180, segments = 24} }}
end

-- smiley loops for size s (mm): face circle, two eyes, crescent mouth
local function smiley_loops(s, rev)
	local r = s / 2
	local eye = r * 0.12
	local outer = circle_loop(0, 0, r)
	local eye_l = circle_loop(-r * 0.36, r * 0.28, eye, rev)
	local eye_r = circle_loop(r * 0.36, r * 0.28, eye, rev)
	local mouth = {
		{ {mm(-r * 0.58), mm(-r * 0.12)}, {mm(r * 0.58), mm(-r * 0.12)} },
		{ {angle = 150, segments = 24}, {angle = -85, segments = 24} },	--deep arc out, shallower arc back = crescent
	}
	if rev then
		mouth[2] = { {angle = 85, segments = 24}, {angle = -150, segments = 24} }
	end
	return outer, eye_l, eye_r, mouth
end

-- warning sign loops for size s (mm): triangle, bar, dot
local function warning_loops(s, rev)
	local w, h = s, s * 0.866
	local tri = {{ {mm(-w / 2), 0}, {mm(w / 2), 0}, {mm(0), mm(h)} }}
	local bar = {{ {mm(-s * 0.05), mm(h * 0.30)}, {mm(s * 0.05), mm(h * 0.30)}, {mm(s * 0.035), mm(h * 0.70)}, {mm(-s * 0.035), mm(h * 0.70)} }}
	if rev then
		bar = {{ {mm(-s * 0.05), mm(h * 0.30)}, {mm(-s * 0.035), mm(h * 0.70)}, {mm(s * 0.035), mm(h * 0.70)}, {mm(s * 0.05), mm(h * 0.30)} }}
	end
	local dot = circle_loop(0, h * 0.14, s * 0.06, rev)
	return tri, bar, dot
end

local function extrude_face(face, thick_mm)
	local out = pytha.create_profile(first(face), mm(thick_mm))
	pcall(function() pytha.delete_element(first(face)) end)	--create_profile keeps its base face
	return first(out)
end

----------------------------------------------------------------------------------------------------------------
-- tests
----------------------------------------------------------------------------------------------------------------
local function run(s)
	local x = 0
	local function nextx() local v = x; x = x + STEP_MM; return v end

	-- A. text: the "baseline" V26 call (the one Group Numbering 1.4 already relies on)
	local ok, h
	ok, h = try("T1 create_text_3d(text,height,thickness) - V26 baseline", function()
		return in_front_plane(nextx(), function() return pytha.create_text_3d("!", mm(s.size_mm), mm(s.thick_mm)) end)
	end)
	if ok then paint(h, s.pen_feature); table.insert(made, h); record("   size", true, size_of(h)) end

	-- B. text with origin + options (font/bold/orientation) - wiki lists these; does V26 take them?
	ok, h = try("T2 create_text_3d with origin + options (Arial, bold, centre) - accepted, effect not proven", function()
		return in_front_plane(nextx(), function()
			return pytha.create_text_3d("!", mm(s.size_mm), mm(s.thick_mm), {0, 0, 0}, {font = "Arial", bold = true, orientation = "center"})
		end)
	end)
	if ok then paint(h, s.pen_feature); table.insert(made, h); record("   size", true, size_of(h)) end

	-- C. emoji glyph through the text path (default font, then an emoji font through the options form)
	ok, h = try("T3 create_text_3d with the emoji character (default font)", function()
		return in_front_plane(nextx(), function() return pytha.create_text_3d("\u{1F642}", mm(s.size_mm), mm(s.thick_mm)) end)
	end)
	if ok then
		paint(h, s.pen_feature); table.insert(made, h)
		local sz = size_of(h)
		record("   size (a tiny or empty box means the font has no emoji glyph)", true, sz)
	end
	ok, h = try("T4 create_text_3d with emoji + font 'Segoe UI Emoji' (options form)", function()
		return in_front_plane(nextx(), function()
			return pytha.create_text_3d("\u{1F642}", mm(s.size_mm), mm(s.thick_mm), {0, 0, 0}, {font = "Segoe UI Emoji"})
		end)
	end)
	if ok then paint(h, s.pen_feature); table.insert(made, h); record("   size", true, size_of(h)) end

	-- D. text as pure linework (edges only, no volume)
	ok, h = try("T5 create_text_engraving - letters as edge curves", function()
		return in_front_plane(nextx(), function() return pytha.create_text_engraving("!", mm(s.size_mm)) end)
	end)
	if ok then paint(h, s.pen_feature); table.insert(made, h); record("   size", true, size_of(h)) end
	ok, h = try("T6 create_text_engraving with options (open contours)", function()
		return in_front_plane(nextx(), function() return pytha.create_text_engraving("!", mm(s.size_mm), {0, 0, 0}, {open = true, font = "Arial"}) end)
	end)
	if ok then paint(h, s.pen_feature); table.insert(made, h); record("   size", true, size_of(h)) end

	-- D2. the emoji as pure linework: contours only, no volume (could be turned into faces/extruded at different heights)
	ok, h = try("T5b create_text_engraving with the emoji character (contours only)", function()
		return in_front_plane(nextx(), function() return pytha.create_text_engraving("\u{1F642}", mm(s.size_mm)) end)
	end)
	if ok then paint(h, s.pen_feature); table.insert(made, h); record("   size (0 thick = edges only; compare the face detail by eye with T3)", true, size_of(h)) end
	ok, h = try("T5c create_text_engraving emoji, font 'Segoe UI Emoji', open contours", function()
		return in_front_plane(nextx(), function() return pytha.create_text_engraving("\u{1F642}", mm(s.size_mm), {0, 0, 0}, {font = "Segoe UI Emoji", open = true}) end)
	end)
	if ok then paint(h, s.pen_feature); table.insert(made, h); record("   size", true, size_of(h)) end

	-- E. smiley, variant 1: ONE face with holes (eyes + mouth are real cut-outs), extruded
	ok, h = try("T7 smiley as one polygon_ex with holes + create_profile", function()
		return in_front_plane(nextx(), function()
			local outer, el, er, mouth = smiley_loops(s.size_mm)
			local face = pytha.create_polygon_ex({outer, el, er, mouth})
			return extrude_face(face, s.thick_mm)
		end)
	end)
	if ok then paint(h, s.pen_body); table.insert(made, h); record("   size", true, size_of(h)) end

	-- E2. diagnose the missing holes: the flat face alone (look at it before any extrusion), then holes wound the other way
	ok, h = try("T7b smiley FACE ONLY (polygon_ex, no extrusion) - holes visible?", function()
		return in_front_plane(nextx(), function()
			local outer, el, er, mouth = smiley_loops(s.size_mm)
			return pytha.create_polygon_ex({outer, el, er, mouth})
		end)
	end)
	if ok then table.insert(made, h); record("   size", true, size_of(h)) end
	ok, h = try("T7c smiley polygon_ex, holes wound opposite, extruded", function()
		return in_front_plane(nextx(), function()
			local outer = smiley_loops(s.size_mm)
			local _, el, er, mouth = smiley_loops(s.size_mm, true)
			return extrude_face(pytha.create_polygon_ex({outer, el, er, mouth}), s.thick_mm)
		end)
	end)
	if ok then paint(h, s.pen_body); table.insert(made, h); record("   size", true, size_of(h)) end

	-- F. smiley, variant 2: layered - disc, plus separate eye/mouth parts sitting on it (different colours possible)
	ok, h = try("T8 smiley layered: disc + raised eyes + raised mouth (3 pens possible)", function()
		return in_front_plane(nextx(), function()
			local outer, el, er, mouth = smiley_loops(s.size_mm)
			local parts = {}
			local disc = extrude_face(pytha.create_polygon_ex({outer}), s.thick_mm)
			paint(disc, s.pen_body); table.insert(parts, disc)
			local token = pytha.push_local_coordinates({0, 0, mm(s.thick_mm)}, {})	--raise features: w points to -y (toward the viewer), so on top of the disc is +w
			local ok2, err = pcall(function()
				for _, loop in ipairs({el, er, mouth}) do
					local f = extrude_face(pytha.create_polygon_ex({loop}), s.thick_mm * 0.5)
					paint(f, s.pen_feature); table.insert(parts, f)
				end
			end)
			pytha.pop_local_coordinates(token)
			if not ok2 then error(err, 0) end
			return pytha.create_group(parts, {name = "Smiley layered"})
		end)
	end)
	if ok then table.insert(made, h); record("   size", true, size_of(h)) end

	-- G. smiley, variant 3: solid disc minus separate eye/mouth solids via boolean difference
	ok, h = try("T9 smiley via boole_part_difference (disc minus eyes/mouth)", function()
		return in_front_plane(nextx(), function()
			local outer, el, er, mouth = smiley_loops(s.size_mm)
			local disc = extrude_face(pytha.create_polygon_ex({outer}), s.thick_mm)
			local cutters = {}
			for _, loop in ipairs({el, er, mouth}) do
				table.insert(cutters, extrude_face(pytha.create_polygon_ex({loop}), s.thick_mm))
			end
			return pytha.boole_part_difference(disc, cutters)
		end)
	end)
	if ok then paint(h, s.pen_body); table.insert(made, h); record("   size", true, size_of(h)) end

	-- H. smiley, variant 4: primitives only (circle + create_ring as a rim) - ring is listed as V27 on the wiki
	ok, h = try("T10 create_ring as a rim (wiki says V27)", function()
		return in_front_plane(nextx(), function()
			return pytha.create_ring(mm(s.size_mm / 2), mm(s.thick_mm / 2))
		end)
	end)
	if ok then paint(h, s.pen_body); table.insert(made, h); record("   size", true, size_of(h)) end

	-- I. smiley, variant 5: pure linework (closed polylines with arcs) - an outline-only icon for plot sheets/2D
	ok, h = try("T11 smiley as linework only (polyline_ex loops)", function()
		return in_front_plane(nextx(), function()
			local r = s.size_mm / 2
			local parts = {}
			local function loop(l) return pytha.create_polyline_ex("closed", l[1], l[2]) end
			local outer, el, er, mouth = smiley_loops(s.size_mm)
			for _, l in ipairs({outer, el, er, mouth}) do table.insert(parts, loop(l)) end
			return pytha.create_group(parts, {name = "Smiley lines"})
		end)
	end)
	if ok then paint(h, s.pen_feature); table.insert(made, h); record("   size", true, size_of(h)) end

	-- J. warning sign, variant 1: triangle with the exclamation cut out, extruded
	ok, h = try("T12 warning triangle with '!' cut-outs (polygon_ex + profile)", function()
		return in_front_plane(nextx(), function()
			local tri, bar, dot = warning_loops(s.size_mm)
			local face = pytha.create_polygon_ex({tri, bar, dot})
			return extrude_face(face, s.thick_mm)
		end)
	end)
	if ok then paint(h, s.pen_body); table.insert(made, h); record("   size", true, size_of(h)) end

	ok, h = try("T12b warning polygon_ex, holes wound opposite, extruded", function()
		return in_front_plane(nextx(), function()
			local tri = warning_loops(s.size_mm)
			local _, bar, dot = warning_loops(s.size_mm, true)
			return extrude_face(pytha.create_polygon_ex({tri, bar, dot}), s.thick_mm)
		end)
	end)
	if ok then paint(h, s.pen_body); table.insert(made, h); record("   size", true, size_of(h)) end
	ok, h = try("T12c warning via boole_part_difference (triangle minus bar and dot)", function()
		return in_front_plane(nextx(), function()
			local tri, bar, dot = warning_loops(s.size_mm)
			local base = extrude_face(pytha.create_polygon_ex({tri}), s.thick_mm)
			local cutters = {}
			for _, loop in ipairs({bar, dot}) do
				table.insert(cutters, extrude_face(pytha.create_polygon_ex({loop}), s.thick_mm))
			end
			return pytha.boole_part_difference(base, cutters)
		end)
	end)
	if ok then paint(h, s.pen_body); table.insert(made, h); record("   size", true, size_of(h)) end

	-- K. warning sign, variant 2: layered triangle + raised "!" bar and dot in a second pen
	ok, h = try("T13 warning layered: triangle + raised '!' (2 pens possible)", function()
		return in_front_plane(nextx(), function()
			local tri, bar, dot = warning_loops(s.size_mm)
			local parts = {}
			local base = extrude_face(pytha.create_polygon_ex({tri}), s.thick_mm)
			paint(base, s.pen_body); table.insert(parts, base)
			local token = pytha.push_local_coordinates({0, 0, mm(s.thick_mm)}, {})
			local ok2, err = pcall(function()
				for _, loop in ipairs({bar, dot}) do
					local f = extrude_face(pytha.create_polygon_ex({loop}), s.thick_mm * 0.5)
					paint(f, s.pen_feature); table.insert(parts, f)
				end
			end)
			pytha.pop_local_coordinates(token)
			if not ok2 then error(err, 0) end
			return pytha.create_group(parts, {name = "Warning layered"})
		end)
	end)
	if ok then table.insert(made, h); record("   size", true, size_of(h)) end

end

----------------------------------------------------------------------------------------------------------------
-- dialog + report
----------------------------------------------------------------------------------------------------------------
local function dialog_fn(dialog, s)
	dialog:set_window_title(pyloc "Glyph Lab 0.6")
	dialog:create_standalone_label({1, 2}, pyloc "Builds a smiley and a warning sign several ways and reports what this PYTHA accepts.")
	dialog:create_label(1, pyloc "Glyph size (mm)")
	local size = dialog:create_text_box(2, pyui.format_number(s.size_mm))
	size:set_on_change_handler(function(text)
		local n = pyui.parse_number(text)
		if n ~= nil and n >= 10 and n <= 1000 then s.size_mm = n end
	end)
	dialog:create_label(1, pyloc "Thickness (mm)")
	local thick = dialog:create_text_box(2, pyui.format_number(s.thick_mm))
	thick:set_on_change_handler(function(text)
		local n = pyui.parse_number(text)
		if n ~= nil and n >= 0.5 and n <= 200 then s.thick_mm = n end
	end)
	dialog:create_label(1, pyloc "Body pen (0 = leave)")
	local pb = dialog:create_text_box(2, pyui.format_number(s.pen_body))
	pb:set_on_change_handler(function(text)
		local n = pyui.parse_number(text)
		if n ~= nil and n >= 0 and n <= 256 then s.pen_body = math.floor(n) end
	end)
	dialog:create_label(1, pyloc "Feature pen (0 = leave)")
	local pf = dialog:create_text_box(2, pyui.format_number(s.pen_feature))
	pf:set_on_change_handler(function(text)
		local n = pyui.parse_number(text)
		if n ~= nil and n >= 0 and n <= 256 then s.pen_feature = math.floor(n) end
	end)
	local st = dialog:create_check_box({1, 2}, pyloc "Also test plot-sheet calls (makes a sheet 'Glyph Lab sheet')")
	st:set_control_checked(s.sheet_tests)
	st:set_on_click_handler(function(state) s.sheet_tests = state end)
	local ks = dialog:create_check_box({1, 2}, pyloc "Keep that sheet afterwards (otherwise it is deleted)")
	ks:set_control_checked(s.keep_sheet)
	ks:set_on_click_handler(function(state) s.keep_sheet = state end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

local function sheet_tests(s, group)
	local ok, sheet = try("S1 pyplot.create_sheet('Glyph Lab sheet') - wiki says V26", function()
		return pyplot.create_sheet("Glyph Lab sheet")
	end)
	if not ok then return end
	--the sheet's length unit is not documented: 0.3 sent mm numbers to an inch Letter sheet and the sheet looked empty.
	--So every sheet call is made twice, once with mm numbers (A) and once with numbers in the document unit (B), and the
	--scale is derived from the group's real width so the view fits the page either way.
	local w_doc = nil
	if group ~= nil then
		local okb, bb = pcall(function() return pytha.get_element_bounding_box(group) end)
		if okb and type(bb) == "table" and bb[1] and bb[2] then w_doc = math.abs(bb[2][1] - bb[1][1]) end
	end
	record("   group width in document units", w_doc ~= nil, w_doc and string.format("%.2f %s", w_doc, pytha.get_length_unit()) or "unknown")
	--0.5 result (by eye): detail POSITION = centre of the view, in document units (inches here); text SIZE is mm;
	--view_min/view_max clip with NO scale placed and fitted the view; the explicit-scale calls (C1/C2) showed nothing.
	--0.6 turns that into a helper, place_view(), and tries a three-view layout with labels and a title block.
	local function B(v) return to_doc(v) end
	local bbg
	if group ~= nil then
		local okb2, bb2 = pcall(function() return pytha.get_element_bounding_box(group) end)
		if okb2 and type(bb2) == "table" then bbg = bb2 end
	end
	if not bbg then record("S2 bounding box for the group", false, "unavailable - views skipped"); return end
	local lo, hi = bbg[1], bbg[2]
	local function span(i) return math.abs(hi[i] - lo[i]) end
	--axes of each view: which model axes are the view's horizontal / vertical
	local VIEWS = {
		{name = "xz", h = 1, v = 3, label = "FRONT"},
		{name = "xy", h = 1, v = 2, label = "TOP"},
		{name = "yz", h = 2, v = 3, label = "SIDE"},
	}
	--place_view: fits the clipped view into a box of max_w x max_h (document units), centred at (cx, cy)
	local function place_view(sheet_, group_, vw, cx, cy, max_w, max_h)
		local w, h = span(vw.h), span(vw.v)
		if w <= 0 or h <= 0 then return nil, "zero extent" end
		local k = math.min(max_w / w, max_h / h)
		return pyplot.insert_detail(sheet_, {
			view = vw.name, position = {cx, cy}, size = {w * k, h * k},
			view_min = {lo[vw.h], lo[vw.v]}, view_max = {hi[vw.h], hi[vw.v]},
		}, {group_})
	end
	--layout in inches on a Letter landscape sheet (11 x 8.5), frame about 0.4 in in
	local cols = {{2.8, 6.4}, {8.2, 6.4}, {2.8, 3.0}}
	for i, vw in ipairs(VIEWS) do
		local c = cols[i]
		try("L" .. i .. " place_view " .. vw.name .. " (" .. vw.label .. ") centred at (" .. c[1] .. ", " .. c[2] .. ") in, via view_min/view_max", function()
			return place_view(sheet, group, vw, B(c[1] * 25.4), B(c[2] * 25.4), B(4.6 * 25.4), B(1.8 * 25.4))
		end)
		try("L" .. i .. "t label " .. vw.label, function()
			return pyplot.insert_text(sheet, vw.label .. " VIEW", {size = 4, position = {B(c[1] * 25.4 - 0.5 * 25.4), B((c[2] - 1.2) * 25.4)}, bold = true, font = "Arial"})
		end)
	end
	--title block: name, number, date, all as plain sheet text
	try("L4 title block texts", function()
		pyplot.insert_text(sheet, "GLYPH LAB - ELEVATIONS", {size = 6, position = {B(0.6 * 25.4), B(1.1 * 25.4)}, bold = true, font = "Arial"})
		pyplot.insert_text(sheet, "A-101", {size = 9, position = {B(8.6 * 25.4), B(1.1 * 25.4)}, bold = true, font = "Arial"})
		pyplot.insert_text(sheet, "Pytha V26, compiled 2026-07-20 14:19:45", {size = 3, position = {B(0.6 * 25.4), B(0.75 * 25.4)}, font = "Arial"})
	end)
	--pydim: the 0.3 run showed the whole namespace is missing on this build ("global 'pydim' is nil"). Keep the probe, but say so plainly.
	if type(pydim) ~= "table" then
		record("S5 pydim.create_text", false, "the pydim namespace does not exist on this build (global pydim is nil) - a real V27 wall")
	else
		local okd, t = try("S5 pydim.create_text", function()
			return pydim.create_text("ELEV A", {{0, 0, 0}}, {view = "xz", style = {size = 6}})
		end)
		if okd and t ~= nil then pcall(function() pytha.delete_element(t) end) end
	end
	if not s.keep_sheet then
		try("S6 pyplot.delete_sheet", function() pyplot.delete_sheet(sheet) end)
	end
end

function glyph_lab()
	local s = {}
	for k, v in pairs(DEFAULTS) do s[k] = v end
	local ok_load, saved = pcall(function() return pyio.load_values("glyph_lab_settings") end)
	if ok_load and type(saved) == "table" then
		for k, v in pairs(saved) do
			if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then s[k] = v end
		end
	end
	if pyui.run_modal_subdialog(dialog_fn, s) ~= "ok" then return end
	pcall(function() pyio.save_values("glyph_lab_settings", s) end)

	results, made = {}, {}
	-- a re-run replaces the old test group
	local old_groups = {}		--collect first: deleting while enumerate_groups is still looping can skip groups
	for g in pytha.enumerate_groups() do
		local ok_n, n = pcall(function() return pytha.get_element_attribute(g, 3) end)
		if ok_n and tostring(n) == GROUP_NAME and pytha.get_element_parent_group(g) == nil then
			table.insert(old_groups, g)
		end
	end
	for _, g in ipairs(old_groups) do
		pcall(function() pytha.delete_element(g) end)
	end
	local ok_run, err = pcall(run, s)
	if not ok_run then record("run aborted", false, err) end
	local group
	if #made > 0 then
		local flat = {}
		for _, m in ipairs(made) do table.insert(flat, first(m)) end
		local okg, g = pcall(function() return pytha.create_group(flat, {name = GROUP_NAME}) end)
		if okg then group = g end
	end
	if s.sheet_tests then
		local oks, errs = pcall(sheet_tests, s, group)
		if not oks then record("sheet tests aborted", false, errs) end
	end

	local lines, passed, failed = {"Glyph Lab 0.6 report", ""}, 0, 0
	for _, r in ipairs(results) do
		if r[2] then passed = passed + 1 else failed = failed + 1 end
		table.insert(lines, (r[2] and "[ok]   " or "[FAIL] ") .. r[1] .. (r[3] ~= "ok" and r[3] ~= "" and ("  ->  " .. r[3]) or ""))
	end
	table.insert(lines, "")
	table.insert(lines, passed .. " ok, " .. failed .. " failed. Variants are in the group '" .. GROUP_NAME .. "' (front view, left to right).\nNot tested: saving a glyph as a .pyo library element from Lua (no such call seen in the wiki index) - do it by hand.")
	local text = table.concat(lines, "\n")
	local saved_to = ""
	local ok_w = pcall(function()
		pyio.write_lines(pyio.get_scratch_folder_path("glyph_lab_report.txt"), lines)
	end)
	if ok_w then saved_to = "\n\nReport also saved as glyph_lab_report.txt in the plugin scratch folder." end
	pyui.alert(text .. saved_to)
end

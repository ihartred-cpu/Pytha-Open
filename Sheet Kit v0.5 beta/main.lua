-- Sheet Kit v0.5 BETA (2026-10-15) - lays out front / top / side views of the model (or the groups you pick) on a NEW plot sheet,
-- with view labels and a title block (title, sheet number, scale, date). Built only from calls that Glyph Lab 0.5/0.6
-- showed working on PYTHA V26 (compiled 2026-07-20 14:19:45): pyplot.create_sheet / insert_detail / insert_text.
--
-- What Glyph Lab observed (by eye, Letter landscape sheet, inch document):
--   * insert_detail with view_min/view_max and NO scale: places and fits the view. Position = CENTRE of the view, document units.
--   * insert_text: position = TOP-LEFT of the text (it hangs down from y), document units; size is in MM.
--   * pydim (model dimensions/annotations) does not exist on this build; nothing here uses it.
-- NOT verified: top/side view orientation on a model with real depth (check the first sheet!), sheet sizes other than
-- Letter landscape (the layout constants below assume 11 x 8.5 in), non-inch documents.

--sheet presets, inches. drawing_area = drawing area above the title strip (left/top = its corner); text_scale = text size factor (Letter = 1)
local PAPERS = {
	letter = {width = 11, height = 8.5, drawing_area = {left = 0.7, top = 1.7, width = 9.6, height = 6.1}, view_gap = 0.7, text_scale = 1},
	archd = {width = 36, height = 24, drawing_area = {left = 1.0, top = 3.0, width = 34.0, height = 19.8}, view_gap = 1.5, text_scale = 2.4},
}
local DRAWING_AREA, VIEW_GAP_INCHES, TEXT_SCALE = PAPERS.archd.drawing_area, PAPERS.archd.view_gap, PAPERS.archd.text_scale	--set from the dialog before drawing
local SKIP_GROUPS = {["Group Numbers"] = true, ["Glyph Lab"] = true}
--US architectural scales: inches on the sheet per foot of model -> ratio = 12 / that. Smallest drawn scale is 1/8" = 1'-0".
local SCALES = {
	{inches_per_foot = 0.125, name = "1/8"}, {inches_per_foot = 0.1875, name = "3/16"}, {inches_per_foot = 0.25, name = "1/4"}, {inches_per_foot = 0.375, name = "3/8"},
	{inches_per_foot = 0.5, name = "1/2"}, {inches_per_foot = 0.75, name = "3/4"}, {inches_per_foot = 1, name = "1"}, {inches_per_foot = 1.5, name = "1-1/2"},
	{inches_per_foot = 3, name = "3"}, {inches_per_foot = 6, name = "6"}, {inches_per_foot = 12, name = "12"},
}

local DEFAULTS = {sheet_name = "Elevations", title = "ELEVATIONS", number = "A-101", scale = "", paper = "archd", explicit = true, pick = false, levels = "0", each = false}		--scale: "" = auto, else inches per foot, e.g. 3/4 or 1-1/2

----------------------------------------------------------------------------------------------------------------
-- SheetKit: the reusable part (copy this block into another plugin; `require` between plugins is untested)
----------------------------------------------------------------------------------------------------------------
local SheetKit = {}

function SheetKit.to_doc(value_mm)							--mm -> document units
	if pytha.get_length_unit() == "in" then return value_mm / 25.4 end
	return value_mm
end
function SheetKit.in_to_doc(value_in) return SheetKit.to_doc(value_in * 25.4) end

--union bounding box {{x,y,z},{x,y,z}} of the top-level groups (or of `groups` if given), skipping helper groups
function SheetKit.model_bounds(groups, include_all)
	local low, high, count, skipped = nil, nil, 0, 0
	local function add_box(group)
		local call_ok, box = pcall(function() return pytha.get_element_bounding_box(group) end)
		if not (call_ok and type(box) == "table" and box[1] and box[2]) then return end
		count = count + 1
		low = low or {box[1][1], box[1][2], box[1][3]}
		high = high or {box[2][1], box[2][2], box[2][3]}
		for axis = 1, 3 do
			low[axis] = math.min(low[axis], box[1][axis], box[2][axis])
			high[axis] = math.max(high[axis], box[1][axis], box[2][axis])
		end
	end
	if groups then
		for _, group in ipairs(groups) do add_box(group) end
	else
		for group in pytha.enumerate_groups() do
			if pytha.get_element_parent_group(group) == nil then
				local call_ok, group_name = pcall(function() return tostring(pytha.get_element_attribute(group, 3)) end)
				if call_ok and SKIP_GROUPS[group_name] and not include_all then skipped = skipped + 1 else add_box(group) end
			end
		end
	end
	if count == 0 then return nil, 0, skipped end
	return {low, high}, count, skipped
end

--place one orthographic view: centre (centre_x, centre_y) and size (width, height) in document units, clipped to the bounds box
--axes: h_axis and v_axis are the model axis indices (1=x, 2=y, 3=z) that run horizontally / vertically in that view
function SheetKit.place_view(sheet, view, bounds, h_axis, v_axis, centre_x, centre_y, width, height, elements)
	return pyplot.insert_detail(sheet, {
		view = view, position = {centre_x, centre_y}, size = {width, height},
		view_min = {bounds[1][h_axis], bounds[1][v_axis]},
		view_max = {bounds[2][h_axis], bounds[2][v_axis]},
	}, elements)
end

--same, with an explicit scale. Seen on V26 (View Lab 0.3): `scale` is the DENOMINATOR (1/8" = 1' -> 96), the view's origin
--(model 0,0 on that view's axes) lands on `position`, and `size` is a crop frame centred on `position`. So to centre the
--model's box on (centre_x, centre_y) the position is shifted by minus the box centre / scale, and the frame is enlarged to still hold it.
--view_min/view_max are not used. (All inferred from one test model whose box started at 0,0,0: re-check on a model that does not.)
function SheetKit.place_view_scaled(sheet, view, bounds, h_axis, v_axis, centre_x, centre_y, width, height, ratio, elements)
	local model_centre_h = (bounds[1][h_axis] + bounds[2][h_axis]) / 2
	local model_centre_v = (bounds[1][v_axis] + bounds[2][v_axis]) / 2
	local margin = 0.2 * DRAWING_AREA.width / 10
	--the crop frame is centred on `position`, which is shifted off the box centre, so the frame must be big enough to still hold the box
	local frame_width = 2 * (math.abs(model_centre_h / ratio) + width / 2) + margin
	local frame_height = 2 * (math.abs(model_centre_v / ratio) + height / 2) + margin
	return pyplot.insert_detail(sheet, {
		view = view, position = {centre_x - model_centre_h / ratio, centre_y - model_centre_v / ratio}, size = {frame_width, frame_height}, scale = ratio,
	}, elements)
end

--text: left_x, top_y = TOP-LEFT in document units, size in mm
function SheetKit.text(sheet, text_string, left_x, top_y, size_mm, bold)
	return pyplot.insert_text(sheet, text_string, {size = size_mm, position = {left_x, top_y}, bold = bold or false, font = "Arial"})
end

--inches-per-foot text ("3/4", "1-1/2", "1", "3") -> number, or nil
function SheetKit.parse_inches_per_foot(text)
	text = tostring(text or ""):gsub("[%s\"']", ""):gsub("=1.*", "")
	if text == "" then return nil end
	local whole, numerator, denominator = text:match("^(%d+)%-(%d+)/(%d+)$")
	if whole then return tonumber(whole) + tonumber(numerator) / tonumber(denominator) end
	numerator, denominator = text:match("^(%d+)/(%d+)$")
	if numerator then return tonumber(numerator) / tonumber(denominator) end
	return tonumber(text)
end

function SheetKit.scale_label(scale_entry)
	if scale_entry.inches_per_foot >= 12 then return "FULL SIZE" end
	return scale_entry.name .. "\" = 1'-0\""
end

--auto: the largest listed scale whose views still fit (fit_ratio = largest sheet/model ratio that fits).
--typed: the listed scale closest to what was typed. Returns scale entry and whether the views fit the drawing area.
function SheetKit.pick_scale(fit_ratio, typed_inches_per_foot)
	local want = typed_inches_per_foot
	if want == nil then
		want = SCALES[1].inches_per_foot
		for _, scale_entry in ipairs(SCALES) do
			if scale_entry.inches_per_foot / 12 <= fit_ratio then want = scale_entry.inches_per_foot end
		end
	end
	local best = SCALES[1]
	for _, scale_entry in ipairs(SCALES) do
		if math.abs(scale_entry.inches_per_foot - want) < math.abs(best.inches_per_foot - want) then best = scale_entry end
	end
	return best, best.inches_per_foot / 12 <= fit_ratio * 1.0001
end

function SheetKit.new_sheet(name)
	local call_ok, sheet = pcall(function() return pyplot.create_sheet(name) end)
	if call_ok then return sheet, name end
	for suffix = 2, 9 do
		local attempt_name = name .. " " .. suffix
		local attempt_ok, attempt_sheet = pcall(function() return pyplot.create_sheet(attempt_name) end)
		if attempt_ok then return attempt_sheet, attempt_name end
	end
	error("could not create a sheet named '" .. name .. "': " .. tostring(sheet))
end

--let the user click parts in the model and return the group(s) around them. levels: 0 = the group directly around the clicked
--part, 1 = that group's parent group, ... (stops at the top-level group). Returns a list of group handles, nil if cancelled.
function SheetKit.pick_groups(levels)
	local call_ok, selection = pcall(function() return pyux.select_part(true, pyloc "Click the cabinet(s) / group(s) to draw, then confirm") end)
	if not call_ok then error("pyux.select_part is not available on this build: " .. tostring(selection)) end
	if selection == nil or selection[1] == nil then return nil end
	local picked_groups = {}
	for _, element in ipairs(selection) do
		local group = element
		local type_ok, element_type = pcall(function() return pytha.get_element_type(element) end)
		if not (type_ok and element_type == "group") then
			local parent_group = pytha.get_element_parent_group(element)
			if parent_group ~= nil then group = parent_group end
		end
		for _ = 1, levels do
			local parent_group = pytha.get_element_parent_group(group)
			if parent_group == nil then break end
			group = parent_group
		end
		local duplicate = false
		for _, existing_group in ipairs(picked_groups) do if existing_group == group then duplicate = true end end
		if not duplicate then table.insert(picked_groups, group) end
	end
	return picked_groups
end

--one line per group for the confirmation dialog: name and size in document units
function SheetKit.describe_group(group)
	local name_ok, group_name = pcall(function() return tostring(pytha.get_element_attribute(group, 3)) end)
	if not name_ok or group_name == "" or group_name == "nil" then group_name = "(unnamed group)" end
	local box_ok, box = pcall(function() return pytha.get_element_bounding_box(group) end)
	if box_ok and type(box) == "table" and box[1] and box[2] then
		return string.format("%s   %.1f x %.1f x %.1f %s", group_name, math.abs(box[2][1] - box[1][1]), math.abs(box[2][2] - box[1][2]),
			math.abs(box[2][3] - box[1][3]), pytha.get_length_unit())
	end
	return group_name
end

--the whole layout: third-angle (top above front, side to the right of front), one common scale, labels, title block
function SheetKit.elevations_sheet(options)
	local paper_preset = PAPERS[tostring(options.paper or ""):lower():gsub("[%s%-_]", "")] or PAPERS.archd
	DRAWING_AREA, VIEW_GAP_INCHES, TEXT_SCALE = paper_preset.drawing_area, paper_preset.view_gap, paper_preset.text_scale
	local bounds, group_count, skipped = SheetKit.model_bounds(options.groups)
	if not bounds and not options.groups and skipped > 0 then bounds, group_count = SheetKit.model_bounds(nil, true) end		--only helper groups exist: draw them
	if not bounds then error("no top-level groups found to draw (loose parts outside a group are not scanned; put them in a group)") end
	local doc_units_per_mm = SheetKit.to_doc(1)							--document units per mm
	local function span_mm(axis) return math.max(1, math.abs(bounds[2][axis] - bounds[1][axis]) / doc_units_per_mm) end
	local front_width_mm, front_height_mm = span_mm(1), span_mm(3)					--front: x by z
	local top_depth_mm = span_mm(2)									--top: x by y
	local side_width_mm = top_depth_mm											--side: y by z
	local fit_ratio = math.min((DRAWING_AREA.width - VIEW_GAP_INCHES) * 25.4 / (front_width_mm + side_width_mm), (DRAWING_AREA.height - VIEW_GAP_INCHES) * 25.4 / (front_height_mm + top_depth_mm))
	local scale_entry, fits = SheetKit.pick_scale(fit_ratio, SheetKit.parse_inches_per_foot(options.scale))
	local ratio = 12 / scale_entry.inches_per_foot
	local model_to_sheet = 1 / ratio
	local function mm_to_sheet_inches(model_mm) return model_mm * model_to_sheet / 25.4 end		--model mm -> sheet inches
	local front_width_in, front_height_in, side_width_in, top_height_in = mm_to_sheet_inches(front_width_mm), mm_to_sheet_inches(front_height_mm), mm_to_sheet_inches(side_width_mm), mm_to_sheet_inches(top_depth_mm)
	local total_width, total_height = front_width_in + VIEW_GAP_INCHES + side_width_in, front_height_in + VIEW_GAP_INCHES + top_height_in
	local origin_x = DRAWING_AREA.left + (DRAWING_AREA.width - total_width) / 2
	local origin_y = DRAWING_AREA.top + (DRAWING_AREA.height - total_height) / 2
	local inches_to_doc = SheetKit.in_to_doc
	local sheet, used_name = SheetKit.new_sheet(options.sheet_name)
	local placed = {}
	local function add_view(label, view, horizontal_axis, vertical_axis, centre_x, centre_y, width, height)
		if options.explicit then
			SheetKit.place_view_scaled(sheet, view, bounds, horizontal_axis, vertical_axis, inches_to_doc(centre_x), inches_to_doc(centre_y), inches_to_doc(width), inches_to_doc(height), ratio, options.groups)
		else
			SheetKit.place_view(sheet, view, bounds, horizontal_axis, vertical_axis, inches_to_doc(centre_x), inches_to_doc(centre_y), inches_to_doc(width), inches_to_doc(height), options.groups)
		end
		SheetKit.text(sheet, label, inches_to_doc(centre_x - width / 2), inches_to_doc(centre_y - height / 2 - 0.1 * TEXT_SCALE), 4 * TEXT_SCALE, true)		--hangs down from just below the view
		table.insert(placed, label)
	end
	add_view("FRONT", "xz", 1, 3, origin_x + front_width_in / 2, origin_y + front_height_in / 2, front_width_in, front_height_in)
	add_view("TOP", "xy", 1, 2, origin_x + front_width_in / 2, origin_y + front_height_in + VIEW_GAP_INCHES + top_height_in / 2, front_width_in, top_height_in)
	add_view("SIDE", "yz", 2, 3, origin_x + front_width_in + VIEW_GAP_INCHES + side_width_in / 2, origin_y + front_height_in / 2, side_width_in, front_height_in)
	local date = ""
	pcall(function() date = os.date("%Y-%m-%d") end)
	local title_x, title_y = DRAWING_AREA.left, DRAWING_AREA.top - 0.35 * TEXT_SCALE
	SheetKit.text(sheet, options.title, inches_to_doc(title_x), inches_to_doc(title_y), 6 * TEXT_SCALE, true)
	SheetKit.text(sheet, options.number, inches_to_doc(DRAWING_AREA.left + DRAWING_AREA.width - 1.7 * TEXT_SCALE), inches_to_doc(title_y), 9 * TEXT_SCALE, true)
	SheetKit.text(sheet, "Scale " .. SheetKit.scale_label(scale_entry) .. "   " .. date, inches_to_doc(title_x), inches_to_doc(title_y - 0.4 * TEXT_SCALE), 3 * TEXT_SCALE, false)
	return {sheet = sheet, name = used_name, scale = SheetKit.scale_label(scale_entry), fits = fits, groups = group_count, views = placed}
end

----------------------------------------------------------------------------------------------------------------
-- plugin entry
----------------------------------------------------------------------------------------------------------------
local function dialog_fn(dialog, settings)
	dialog:set_window_title(pyloc "Sheet Kit 0.5 (beta)")
	dialog:create_standalone_label({1, 2}, pyloc "Makes a new plot sheet with front, top and side views of the model (or the groups you pick), view labels and a title block.")
	dialog:create_label(1, pyloc "Sheet name")
	local name_box = dialog:create_text_box(2, settings.sheet_name)
	name_box:set_on_change_handler(function(text) if text ~= "" then settings.sheet_name = text end end)
	dialog:create_label(1, pyloc "Title")
	local title_box = dialog:create_text_box(2, settings.title)
	title_box:set_on_change_handler(function(text) settings.title = text end)
	dialog:create_label(1, pyloc "Sheet number")
	local number_box = dialog:create_text_box(2, settings.number)
	number_box:set_on_change_handler(function(text) settings.number = text end)
	dialog:create_label(1, pyloc "Scale, inches per foot (blank = auto)")
	local scale_box = dialog:create_text_box(2, settings.scale)
	scale_box:set_on_change_handler(function(text) settings.scale = text end)
	dialog:create_label(1, pyloc "Sheet size (archd or letter)")
	local paper_box = dialog:create_text_box(2, settings.paper)
	paper_box:set_on_change_handler(function(text) settings.paper = text end)
	local explicit_check = dialog:create_check_box({1, 2}, pyloc "Set the real view scale (untick for the old fit-to-size method)")
	explicit_check:set_control_checked(settings.explicit)
	explicit_check:set_on_click_handler(function(state) settings.explicit = state end)
	local pick_check = dialog:create_check_box({1, 2}, pyloc "Only draw groups I click in the model (you pick them after OK)")
	pick_check:set_control_checked(settings.pick)
	pick_check:set_on_click_handler(function(state) settings.pick = state end)
	local each_check = dialog:create_check_box({1, 2}, pyloc "...and make one sheet per picked group (otherwise all picked groups share one sheet)")
	each_check:set_control_checked(settings.each)
	each_check:set_on_click_handler(function(state) settings.each = state end)
	dialog:create_label(1, pyloc "Levels up from the clicked part (0 = group around it)")
	local levels_box = dialog:create_text_box(2, settings.levels)
	levels_box:set_on_change_handler(function(text) settings.levels = text end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

function sheet_kit()
	local settings = {}
	for key, value in pairs(DEFAULTS) do settings[key] = value end
	local ok_load, saved = pcall(function() return pyio.load_values("sheet_kit_settings") end)
	if ok_load and type(saved) == "table" then
		for key, value in pairs(saved) do
			if DEFAULTS[key] ~= nil and type(value) == type(DEFAULTS[key]) then settings[key] = value end
		end
	end
	if pyui.run_modal_subdialog(dialog_fn, settings) ~= "ok" then return end
	pcall(function() pyio.save_values("sheet_kit_settings", {sheet_name = settings.sheet_name, title = settings.title, number = settings.number, scale = settings.scale, paper = settings.paper, explicit = settings.explicit, pick = settings.pick, levels = settings.levels, each = settings.each}) end)
	settings.groups = nil
	local jobs = {settings}
	if settings.pick then
		local pick_ok, picked = pcall(SheetKit.pick_groups, math.max(0, math.floor(tonumber(settings.levels) or 0)))
		if not pick_ok then pyui.alert("Sheet Kit stopped: " .. tostring(picked)); return end
		if picked == nil or #picked == 0 then return end
		--show what was actually picked (clicking selects parts, so a neighbour's part can slip in) and let the user back out
		local group_lines = {}
		for _, group in ipairs(picked) do
			table.insert(group_lines, SheetKit.describe_group(group))
			pcall(function() pyux.highlight_element(group) end)
		end
		local function confirm_fn(dialog, confirm_state)
			dialog:set_window_title(pyloc "Sheet Kit: confirm groups")
			dialog:create_standalone_label({1, 2}, #picked .. " group(s) picked (highlighted in the model):")
			for _, line in ipairs(group_lines) do dialog:create_standalone_label({1, 2}, line) end
			dialog:create_ok_button(1)
			dialog:create_cancel_button(2)
			dialog:equalize_column_widths({1, 2})
		end
		local answer = pyui.run_modal_subdialog(confirm_fn, {})
		pcall(function() pyux.clear_highlights() end)
		if answer ~= "ok" then return end
		if settings.each and #picked > 1 then
			jobs = {}
			for index, group in ipairs(picked) do
				local job_copy = {}
				for key, value in pairs(settings) do job_copy[key] = value end
				job_copy.groups = {group}
				job_copy.sheet_name = settings.sheet_name .. " " .. index
				table.insert(jobs, job_copy)
			end
		else
			settings.groups = picked
		end
	end
	local made = {}
	for _, job in ipairs(jobs) do
		local call_ok, result = pcall(SheetKit.elevations_sheet, job)
		if not call_ok then
			pyui.alert("Sheet Kit stopped: " .. tostring(result))
			return
		end
		table.insert(made, result)
	end
	if #made > 1 then
		local names = {}
		for _, made_sheet in ipairs(made) do table.insert(names, made_sheet.name .. " (" .. made_sheet.scale .. ")") end
		pyui.alert("Made " .. #made .. " sheets: " .. table.concat(names, ", ") .. ".")
		return
	end
	local result = made[1]
	pyui.alert(string.format("Sheet '%s' made from %d group(s), scale %s.\nViews: %s.%s",
		result.name, result.groups, result.scale, table.concat(result.views, ", "),
		result.fits and "" or "\n\nWARNING: the views do not fit the drawing area at this scale and will overlap or run past the frame. Use a smaller scale, or leave the scale blank for auto (smallest offered is 1/8\" = 1'-0\")."))
end

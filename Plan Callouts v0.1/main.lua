-- Plan Callouts v0.1 (2026-10-18)
-- Reads each cabinet's type (Kitchen Wizard spec), the number written by Group Numbering, and any hardware tags added with
-- "Plan Callouts - Tag hardware", then makes a NEW plot sheet: a plan (top) view with a number and a short code on every cabinet,
-- and a cabinet schedule beside it, run by run ("SINK - DW - DWR STACK 3 - TALL" plus one detail line per cabinet).
-- Built only from calls seen working on V26: pyplot.create_sheet / insert_detail / insert_text (see Sheet Kit's notes).
-- Run Group Numbering first so the numbers exist.
-- NOT verified in PYTHA: how text lands on a plan view drawn with an explicit scale (the position maths is Sheet Kit's), whether the
-- sink model name can be read back from the wizard's stored data, text fit on small cabinets. Check the first sheet.

local TAG_KEY = "plan_callout_tags"				--element-history key for hardware tags on a cabinet group
local WIZARD_HISTORY_KEYS = {"wizard_history"}
local WALL_ROW = 0x2
local SKIP_GROUPS = {["Group Numbers"] = true, ["Glyph Lab"] = true, ["Window Treatments"] = true}

-- edit these lists to suit the shop ------------------------------------------------------------------------------
local HARDWARE = {"TRASH RO", "LEMANS", "UC WINE", "SPICE PULLOUT", "TRAY DIVIDERS", "MIXER LIFT", "LAZY SUSAN", "BLIND CORNER PULLOUT", "WASTE 2-BIN"}
-- Kitchen Wizard cabinet type -> plan code. Anything missing falls back to the type name in capitals.
local TYPE_CODES = {
	sink = "SINK", hob = "COOKTOP", hob_and_oven = "RANGE+OVEN", empty = "OPEN", empty_with_benchtop = "OPEN", empty_wall = "OPEN",
	dishwasher = "DW", fridge = "UC REFER",
	corner = "CORNER", corner_L = "CORNER", corner_L_high = "TALL CORNER", cornerwall = "CORNER WALL",
	diagonal = "DIAG CORNER", diagonal_high = "TALL DIAG", diagonal_wall = "DIAG WALL",
	blind_end = "BLIND END", blind_end_high = "TALL BLIND END", blind_end_wall = "BLIND END",
	rounded_blind_end = "BLIND END", rounded_blind_end_high = "TALL BLIND END", rounded_blind_end_wall = "BLIND END",
	filler = "FILLER", filler_high = "TALL FILLER", filler_wall = "FILLER", angle_piece = "ANGLE", angle_piece_high = "TALL ANGLE", angle_piece_wall = "ANGLE",
	hood = "HOOD", high = "TALL", high_appliance1 = "TALL OVEN", high_appliance2 = "TALL OVEN+MW", high_fridge = "TALL REFER",
	wall = "WALL", top = "TOP", library_straight = "LIBRARY",
}
-- base cabinet front style -> code ("%d" = drawer count)
local BASE_FRONT_CODES = {
	drawers = "DWR STACK %d", intelli_doors = "BASE", intelli_doors_and_drawer = "DOOR+DWR", split_door_drawers = "DOOR / DWR STACK",
	split_open_drawers = "OPEN / DWR STACK", split_door_open = "DOOR / OPEN", open = "OPEN",
}
local GENERIC_CODES = {BASE = true, OPEN = true}		--a hardware tag replaces these instead of being added to them

local PAPERS = {
	letter = {width = 11, height = 8.5, area = {left = 0.7, top = 1.7, width = 9.6, height = 6.1}, text_scale = 1},
	archd = {width = 36, height = 24, area = {left = 1.0, top = 3.0, width = 34.0, height = 19.8}, text_scale = 2.4},
}
local SCALES = {
	{inches_per_foot = 0.125, name = "1/8"}, {inches_per_foot = 0.1875, name = "3/16"}, {inches_per_foot = 0.25, name = "1/4"}, {inches_per_foot = 0.375, name = "3/8"},
	{inches_per_foot = 0.5, name = "1/2"}, {inches_per_foot = 0.75, name = "3/4"}, {inches_per_foot = 1, name = "1"}, {inches_per_foot = 1.5, name = "1-1/2"},
	{inches_per_foot = 3, name = "3"},
}
local DEFAULTS = {sheet_name = "Cabinet Plan", title = "CABINET PLAN", number = "A-102", paper = "archd", scale = "", codes_on_plan = true,
	schedule = true, preview = false}

----------------------------------------------------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------------------------------------------------
local function to_doc_from_in(value_in)
	if pytha.get_length_unit() == "in" then return value_in end
	return value_in * 25.4
end
local function doc_to_in(value_doc)
	if pytha.get_length_unit() == "in" then return value_doc end
	return value_doc / 25.4
end

local function group_name(group)
	local call_ok, name_value = pcall(function() return pytha.get_element_attribute(group, 3) end)
	if call_ok and name_value ~= nil then return tostring(name_value) end
	return ""
end
local function base_name(name) return (name:gsub(" #%d+$", "")) end

local function existing_number(group)
	local call_ok, raw_number = pcall(function() return pytha.get_element_attribute(group, 46) end)
	if not call_ok or raw_number == nil then return nil end
	local number = tonumber(raw_number)
	if number ~= nil and number >= 1 and number == math.floor(number) then return math.floor(number) end
	return nil
end

local function bounding_box(element)
	local call_ok, box = pcall(function() return pytha.get_element_bounding_box(element) end)
	if call_ok and type(box) == "table" and box[1] ~= nil and box[2] ~= nil then return box end
	return nil
end

-- the box of the group's parts (a group's own box also covers reference points)
local function parts_box(group)
	local call_ok, members = pcall(function() return pytha.get_group_descendants(group) end)
	if call_ok and type(members) == "table" then
		local low, high
		for _, element in ipairs(members) do
			local type_ok, kind = pcall(function() return pytha.get_element_type(element) end)
			if type_ok and kind == "part" then
				local box = bounding_box(element)
				if box ~= nil then
					if low == nil then
						low = {math.min(box[1][1], box[2][1]), math.min(box[1][2], box[2][2]), math.min(box[1][3], box[2][3])}
						high = {math.max(box[1][1], box[2][1]), math.max(box[1][2], box[2][2]), math.max(box[1][3], box[2][3])}
					else
						for axis = 1, 3 do
							low[axis] = math.min(low[axis], box[1][axis], box[2][axis])
							high[axis] = math.max(high[axis], box[1][axis], box[2][axis])
						end
					end
				end
			end
		end
		if low ~= nil then return {low, high} end
	end
	return bounding_box(group)
end

local function group_angle(group)
	local call_ok, angle = pcall(function() return pytha.get_group_angle(group) end)
	angle = call_ok and tonumber(angle) or nil
	if angle == nil then return 0 end
	angle = angle % 360
	if angle > 180 then angle = angle - 360 end
	return angle
end

local function run_name(angle)
	local run = math.floor(((90 - angle) % 360) + 0.5) % 360
	local names = {[0] = "LEFT WALL", [90] = "BACK WALL", [180] = "RIGHT WALL", [270] = "FRONT WALL"}
	return names[run] or string.format("RUN %d DEG", run), run
end

local function wizard_data(group)
	for _, key in ipairs(WIZARD_HISTORY_KEYS) do
		local call_ok, data = pcall(function() return pytha.get_element_history(group, key) end)
		if call_ok and type(data) == "table" and type(data.aux_values) == "table" and type(data.aux_values.cabinet_list) == "table" then return data end
	end
	return nil
end

local function read_tags(group)
	local call_ok, stored = pcall(function() return pytha.get_element_history(group, TAG_KEY) end)
	if call_ok and type(stored) == "table" and type(stored.tags) == "table" then
		local tags = {}
		for _, tag in ipairs(stored.tags) do table.insert(tags, tostring(tag)) end
		return tags
	end
	return {}
end

-- the model name of a sink or appliance, if the stored handle can still give it (untested: stored handles may not survive)
local function appliance_name(spec)
	local handle = spec.appliance_file
	if handle == nil then return nil end
	local call_ok, name_value = pcall(function() return handle:get_name() end)
	if call_ok and name_value ~= nil and tostring(name_value) ~= "" then
		return (tostring(name_value):gsub("%.[Pp][Yy][Oo][Xx]?$", ""))
	end
	return nil
end

----------------------------------------------------------------------------------------------------------------
-- description of one cabinet
----------------------------------------------------------------------------------------------------------------
local function describe(spec, tags)
	local this_type = spec.this_type
	local code
	if this_type == "base" then
		local pattern = BASE_FRONT_CODES[spec.front_style or ""] or "BASE"
		if pattern:find("%%d") then
			local drawers = math.floor(tonumber(spec.drawer_count) or 0)
			if drawers > 0 then code = string.format(pattern, drawers) else code = (pattern:gsub(" %%d", "")) end
		else
			code = pattern
		end
	else
		code = TYPE_CODES[this_type or ""]
		if code == nil then code = (tostring(this_type or "CABINET"):upper():gsub("_", " ")) end
	end
	local plan_code, summary_code = code, code
	local detail_parts = {code}
	if this_type == "sink" then
		local sink_model = appliance_name(spec)
		if sink_model ~= nil then table.insert(detail_parts, sink_model) end
	end
	if #tags > 0 then
		local joined = table.concat(tags, " + ")
		if GENERIC_CODES[code] then
			plan_code, summary_code = joined, joined
			detail_parts = {joined}
		else
			plan_code = code .. " + " .. joined
			summary_code = code .. " + " .. joined
			table.insert(detail_parts, joined)
		end
	end
	return {plan_code = plan_code, summary_code = summary_code, detail_parts = detail_parts}
end

----------------------------------------------------------------------------------------------------------------
-- collect every cabinet / group
----------------------------------------------------------------------------------------------------------------
local function collect()
	local items, kitchens = {}, 0
	local top = {}
	for group in pytha.enumerate_groups() do
		if pytha.get_element_parent_group(group) == nil and not SKIP_GROUPS[group_name(group)] then table.insert(top, group) end
	end
	for _, group in ipairs(top) do
		local data = wizard_data(group)
		if data ~= nil then
			kitchens = kitchens + 1
			for _, spec in pairs(data.aux_values.cabinet_list) do
				local cab = type(spec) == "table" and type(spec.aux_values) == "table" and spec.aux_values.main_group or nil
				local in_kitchen = false
				if cab ~= nil then pcall(function() in_kitchen = (pytha.get_element_parent_group(cab) == group) end) end
				local box = in_kitchen and parts_box(cab) or nil
				if box ~= nil then
					local info = describe(spec, read_tags(cab))
					table.insert(items, {group = cab, box = box, tier = (spec.aux_values.row == WALL_ROW) and 2 or 1, angle = group_angle(cab),
						number = existing_number(cab), info = info, width = tonumber(spec.width), wizard = true, spec = spec})
				end
			end
		else
			local box = parts_box(group)
			if box ~= nil then
				local name = base_name(group_name(group))
				local code = (name ~= "" and name:upper()) or "GROUP"
				local tags = read_tags(group)
				local info = {plan_code = code, summary_code = code, detail_parts = {code}}
				if #tags > 0 then
					local joined = table.concat(tags, " + ")
					info = {plan_code = code .. " + " .. joined, summary_code = code .. " + " .. joined, detail_parts = {code, joined}}
				end
				table.insert(items, {group = group, box = box, tier = 1, angle = group_angle(group), number = existing_number(group), info = info, wizard = false})
			end
		end
	end
	for _, item in ipairs(items) do
		item.centre_x = (item.box[1][1] + item.box[2][1]) / 2
		item.centre_y = (item.box[1][2] + item.box[2][2]) / 2
		item.run_label, item.run = run_name(item.angle)
	end
	table.sort(items, function(first, second)
		if first.tier ~= second.tier then return first.tier < second.tier end
		local first_number, second_number = first.number or math.huge, second.number or math.huge
		if first_number ~= second_number then return first_number < second_number end
		if first.run ~= second.run then return first.run < second.run end
		return first.centre_x < second.centre_x
	end)
	return items, kitchens
end

-- schedule lines: per tier and run: a summary line (codes joined with " - ") then one line per cabinet
local function schedule_lines(items)
	local lines = {}
	local tiers = {{1, "BASES / TALLS"}, {2, "UPPERS"}}
	for _, tier in ipairs(tiers) do
		local runs, order = {}, {}
		for _, item in ipairs(items) do
			if item.tier == tier[1] then
				if runs[item.run] == nil then runs[item.run] = {label = item.run_label, list = {}}; table.insert(order, item.run) end
				table.insert(runs[item.run].list, item)
			end
		end
		table.sort(order)
		if #order > 0 then
			table.insert(lines, {text = tier[2], bold = true, gap = true})
			for _, run in ipairs(order) do
				local entry = runs[run]
				local codes = {}
				for _, item in ipairs(entry.list) do table.insert(codes, item.info.summary_code) end
				table.insert(lines, {text = entry.label .. ":  " .. table.concat(codes, " - "), bold = true})
				for _, item in ipairs(entry.list) do
					local number_text = item.number and tostring(item.number) or "-"
					local width_text = ""
					if item.width ~= nil and item.wizard then width_text = "   " .. pyui.format_length(item.width) .. " W" end
					table.insert(lines, {text = string.format("%3s   %s%s", number_text, table.concat(item.info.detail_parts, " - "), width_text), bold = false})
				end
			end
		end
	end
	return lines
end

----------------------------------------------------------------------------------------------------------------
-- sheet
----------------------------------------------------------------------------------------------------------------
local function parse_inches_per_foot(text)
	text = tostring(text or ""):gsub("[%s\"']", ""):gsub("=1.*", "")
	if text == "" then return nil end
	local whole, numerator, denominator = text:match("^(%d+)%-(%d+)/(%d+)$")
	if whole then return tonumber(whole) + tonumber(numerator) / tonumber(denominator) end
	numerator, denominator = text:match("^(%d+)/(%d+)$")
	if numerator then return tonumber(numerator) / tonumber(denominator) end
	return tonumber(text)
end

local function pick_scale(fit_ratio, typed)
	local want = typed
	if want == nil then
		want = SCALES[1].inches_per_foot
		for _, entry in ipairs(SCALES) do if entry.inches_per_foot / 12 <= fit_ratio then want = entry.inches_per_foot end end
	end
	local best = SCALES[1]
	for _, entry in ipairs(SCALES) do
		if math.abs(entry.inches_per_foot - want) < math.abs(best.inches_per_foot - want) then best = entry end
	end
	return best, best.inches_per_foot / 12 <= fit_ratio * 1.0001
end

local function new_sheet(name)
	local call_ok, sheet = pcall(function() return pyplot.create_sheet(name) end)
	if call_ok then return sheet, name end
	for suffix = 2, 9 do
		local attempt_ok, attempt_sheet = pcall(function() return pyplot.create_sheet(name .. " " .. suffix) end)
		if attempt_ok then return attempt_sheet, name .. " " .. suffix end
	end
	error("could not create a sheet named '" .. name .. "': " .. tostring(sheet))
end

local function sheet_text(sheet, text_string, left_x_in, top_y_in, size_mm, bold)
	return pyplot.insert_text(sheet, text_string, {size = size_mm, position = {to_doc_from_in(left_x_in), to_doc_from_in(top_y_in)}, bold = bold or false, font = "Arial"})
end

local function char_width_in(size_mm) return 0.55 * size_mm / 25.4 end

local function build_sheet(items, settings)
	local paper = PAPERS[tostring(settings.paper):lower():gsub("[%s%-_]", "")] or PAPERS.archd
	local area, ts = paper.area, paper.text_scale
	-- model bounds (document units) over all items
	local low, high = {math.huge, math.huge}, {-math.huge, -math.huge}
	for _, item in ipairs(items) do
		for axis = 1, 2 do
			low[axis] = math.min(low[axis], item.box[1][axis], item.box[2][axis])
			high[axis] = math.max(high[axis], item.box[1][axis], item.box[2][axis])
		end
	end
	local bounds = {{low[1], low[2], 0}, {high[1], high[2], 0}}
	local span_x_in, span_y_in = math.max(1, doc_to_in(high[1] - low[1])), math.max(1, doc_to_in(high[2] - low[2]))
	local schedule_width = settings.schedule and 0.30 * area.width or 0
	local plan_w, plan_h = area.width - schedule_width - (settings.schedule and 0.6 * ts or 0), area.height
	local fit_ratio = math.min(plan_w / span_x_in, plan_h / span_y_in)
	local scale_entry, fits = pick_scale(fit_ratio, parse_inches_per_foot(settings.scale))
	local ratio = 12 / scale_entry.inches_per_foot					--model inches per sheet inch
	local plan_cx, plan_cy = area.left + plan_w / 2, area.top + plan_h / 2
	local sheet, used_name = new_sheet(settings.sheet_name)
	local model_cx, model_cy = (low[1] + high[1]) / 2, (low[2] + high[2]) / 2
	local groups = {}
	for _, item in ipairs(items) do table.insert(groups, item.group) end
	-- plan view, scaled; same placement maths as Sheet Kit's place_view_scaled
	local frame_w = 2 * (math.abs(model_cx / ratio) + to_doc_from_in(plan_w) / 2) + 0.2
	local frame_h = 2 * (math.abs(model_cy / ratio) + to_doc_from_in(plan_h) / 2) + 0.2
	pyplot.insert_detail(sheet, {view = "xy", position = {to_doc_from_in(plan_cx) - model_cx / ratio, to_doc_from_in(plan_cy) - model_cy / ratio},
		size = {frame_w, frame_h}, scale = ratio}, groups)
	-- callouts
	local number_mm, code_mm = 3.4 * ts, 2.1 * ts
	local callouts, dropped_codes = 0, 0
	for _, item in ipairs(items) do
		local cab_width_in = item.width and doc_to_in(item.width) / ratio or math.max(doc_to_in(item.box[2][1] - item.box[1][1]), doc_to_in(item.box[2][2] - item.box[1][2])) / ratio
		local number_text = item.number and tostring(item.number) or "-"
		if item.tier == 2 then number_text = "(" .. number_text .. ")" end		--uppers are labelled in brackets, behind the wall
		local number_height_in = number_mm / 25.4 * 1.25
		local words = {}
		for word in item.info.plan_code:gmatch("%S+") do table.insert(words, word) end
		-- wrap words onto lines no wider than the cabinet; shrink the text if a single word is too wide
		local size = code_mm
		local lines = {}
		if settings.codes_on_plan then
			local max_chars = math.max(3, math.floor(cab_width_in / char_width_in(size)))
			local current = ""
			for _, word in ipairs(words) do
				if current == "" then current = word
				elseif #current + 1 + #word <= max_chars then current = current .. " " .. word
				else table.insert(lines, current); current = word end
			end
			if current ~= "" then table.insert(lines, current) end
			local longest = 0
			for _, line in ipairs(lines) do longest = math.max(longest, #line) end
			if longest > 0 and longest * char_width_in(size) > cab_width_in then size = cab_width_in / (longest * 0.55 / 25.4) end
			if size < 1.2 * ts or #lines > 4 then lines = {}; dropped_codes = dropped_codes + 1 end
		end
		local code_height_in = size / 25.4 * 1.25
		local total_height = number_height_in + #lines * code_height_in
		-- bases / talls: label at the cabinet centre. Uppers sit over the bases in plan, so their label goes just behind the cabinet (wall side).
		local label_x, label_y = item.centre_x, item.centre_y
		if item.tier == 2 then
			local angle = math.rad(item.angle or 0)
			local face_x, face_y = math.sin(angle), -math.cos(angle)
			local box_dx, box_dy = doc_to_in(item.box[2][1] - item.box[1][1]), doc_to_in(item.box[2][2] - item.box[1][2])
			local half_depth_in = 0.5 * (math.abs(face_x) * box_dx + math.abs(face_y) * box_dy)
			local push_in = half_depth_in + 0.5 * total_height * ratio + 2
			label_x = item.centre_x - face_x * to_doc_from_in(push_in)
			label_y = item.centre_y - face_y * to_doc_from_in(push_in)
		end
		local sheet_x_in = plan_cx + doc_to_in(label_x - model_cx) / ratio
		local sheet_y_in = plan_cy + doc_to_in(label_y - model_cy) / ratio
		local top_y = sheet_y_in + total_height / 2
		sheet_text(sheet, number_text, sheet_x_in - #number_text * char_width_in(number_mm) / 2, top_y, number_mm, true)
		for index, line in ipairs(lines) do
			sheet_text(sheet, line, sheet_x_in - #line * char_width_in(size) / 2, top_y - number_height_in - (index - 1) * code_height_in, size, false)
		end
		callouts = callouts + 1
	end
	-- title block (plain text, as Sheet Kit)
	local title_y = area.top - 0.35 * ts
	sheet_text(sheet, settings.title, area.left, title_y, 6 * ts, true)
	sheet_text(sheet, settings.number, area.left + area.width - 1.7 * ts, title_y, 9 * ts, true)
	local date = ""
	pcall(function() date = os.date("%Y-%m-%d") end)
	sheet_text(sheet, "Scale " .. scale_entry.name .. "\" = 1'-0\"   " .. date, area.left, title_y - 0.4 * ts, 3 * ts, false)
	-- schedule
	local overflow = 0
	if settings.schedule then
		local lines = schedule_lines(items)
		local left = area.left + plan_w + 0.6 * ts
		local size = 2.6 * ts
		local available = area.height
		local function needed(size_mm)
			local total = 2 * (size_mm / 25.4 * 1.4)
			for _, line in ipairs(lines) do total = total + size_mm / 25.4 * 1.4 + (line.gap and size_mm / 25.4 * 0.6 or 0) end
			return total
		end
		while needed(size) > available and size > 1.3 * ts do size = size - 0.1 * ts end
		local y = area.top + area.height
		sheet_text(sheet, "CABINET SCHEDULE", left, y, size * 1.4, true)
		y = y - 2 * (size / 25.4 * 1.4)
		for _, line in ipairs(lines) do
			if line.gap then y = y - size / 25.4 * 0.6 end
			if y - size / 25.4 < area.top - 0.1 then overflow = overflow + 1 else sheet_text(sheet, line.text, left, y, size, line.bold) end
			y = y - size / 25.4 * 1.4
		end
	end
	return {name = used_name, scale = scale_entry.name, fits = fits, callouts = callouts, dropped_codes = dropped_codes, overflow = overflow}
end

----------------------------------------------------------------------------------------------------------------
-- plugin entries
----------------------------------------------------------------------------------------------------------------
local function dialog_fn(dialog, settings)
	dialog:set_window_title(pyloc "Plan Callouts")
	dialog:create_standalone_label({1, 2}, pyloc "Run Group Numbering first so every cabinet has its number.")
	dialog:create_label(1, pyloc "Sheet name")
	local sheet_name = dialog:create_text_box(2, settings.sheet_name)
	sheet_name:set_on_change_handler(function(text) if text ~= "" then settings.sheet_name = text end end)
	dialog:create_label(1, pyloc "Title")
	local title = dialog:create_text_box(2, settings.title)
	title:set_on_change_handler(function(text) settings.title = text end)
	dialog:create_label(1, pyloc "Sheet number")
	local number = dialog:create_text_box(2, settings.number)
	number:set_on_change_handler(function(text) settings.number = text end)
	dialog:create_label(1, pyloc "Paper (archd or letter)")
	local paper = dialog:create_text_box(2, settings.paper)
	paper:set_on_change_handler(function(text) settings.paper = text end)
	dialog:create_label(1, pyloc "Scale, inches per foot (blank = auto)")
	local scale = dialog:create_text_box(2, settings.scale)
	scale:set_on_change_handler(function(text) settings.scale = text end)
	local codes = dialog:create_check_box({1, 2}, pyloc "Short codes on the plan (not just numbers)")
	codes:set_control_checked(settings.codes_on_plan)
	codes:set_on_click_handler(function(state) settings.codes_on_plan = state end)
	local schedule = dialog:create_check_box({1, 2}, pyloc "Cabinet schedule beside the plan")
	schedule:set_control_checked(settings.schedule)
	schedule:set_on_click_handler(function(state) settings.schedule = state end)
	local preview = dialog:create_check_box({1, 2}, pyloc "Preview only: list what would be drawn, make no sheet")
	preview:set_control_checked(settings.preview)
	preview:set_on_click_handler(function(state) settings.preview = state end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

function plan_callouts()
	local settings = {}
	for key, value in pairs(DEFAULTS) do settings[key] = value end
	local loaded = pyio.load_values("plan_callouts_settings")
	if type(loaded) == "table" then
		for key, value in pairs(loaded) do
			if DEFAULTS[key] ~= nil and type(value) == type(DEFAULTS[key]) then settings[key] = value end
		end
	end
	if pyui.run_modal_subdialog(dialog_fn, settings) ~= "ok" then return end
	pyio.save_values("plan_callouts_settings", settings)
	local items, kitchens = collect()
	if #items == 0 then
		pyui.alert(pyloc "No cabinets or groups found (loose parts outside a group are not scanned).")
		return
	end
	local unnumbered = 0
	for _, item in ipairs(items) do if item.number == nil then unnumbered = unnumbered + 1 end end
	if settings.preview then
		local lines = {string.format("%d cabinets / groups in %d kitchens (%d without a number):", #items, kitchens, unnumbered), ""}
		for _, item in ipairs(schedule_lines(items)) do table.insert(lines, item.text) end
		pyui.alert(table.concat(lines, "\n"))
		return
	end
	local ok, result = pcall(build_sheet, items, settings)
	if not ok then
		pyui.alert(pyloc "Could not build the sheet:" .. "\n" .. tostring(result))
		return
	end
	local notes = {string.format("Sheet '%s' made at %s\" = 1'-0\": %d cabinets.", result.name, result.scale, result.callouts)}
	if not result.fits then table.insert(notes, "The typed scale is too big for the sheet: the plan will run past the frame.") end
	if unnumbered > 0 then table.insert(notes, unnumbered .. " cabinets have no number yet (run Group Numbering).") end
	if result.dropped_codes > 0 then table.insert(notes, result.dropped_codes .. " cabinets are too narrow for a code on the plan: number only (the schedule has it).") end
	if result.overflow > 0 then table.insert(notes, result.overflow .. " schedule lines did not fit under the sheet frame.") end
	pyui.alert(table.concat(notes, "\n"))
end

-- pick cabinets in the model and add / replace / clear hardware tags on them
local function tag_dialog(dialog, data)
	dialog:set_window_title(pyloc "Tag hardware")
	dialog:create_standalone_label({1, 2}, string.format(pyloc "%d cabinet(s) picked", data.count))
	dialog:create_label(1, pyloc "Action")
	local mode = dialog:create_drop_list(2)
	mode:insert_control_item(pyloc "Add tag")
	mode:insert_control_item(pyloc "Replace tags")
	mode:insert_control_item(pyloc "Clear all tags")
	mode:set_control_selection(data.mode)
	mode:set_on_change_handler(function(text, new_index) data.mode = new_index end)
	dialog:create_label(1, pyloc "Hardware")
	local hardware = dialog:create_drop_list(2)
	for _, name in ipairs(HARDWARE) do hardware:insert_control_item(name) end
	hardware:set_control_selection(data.index)
	hardware:set_on_change_handler(function(text, new_index) data.index = new_index end)
	dialog:create_label(1, pyloc "Or your own text")
	local custom = dialog:create_text_box(2, data.custom)
	custom:set_on_change_handler(function(text) data.custom = text end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
end

function tag_hardware()
	local items = collect()
	local picked_ok, selection = pcall(function() return pyux.select_part(true, pyloc "Click the cabinet(s) to tag, then confirm") end)
	if not picked_ok or selection == nil or selection[1] == nil then return end
	local cabinets, seen = {}, {}
	for _, element in ipairs(selection) do
		local node = element
		while node ~= nil do
			local matched = nil
			for _, item in ipairs(items) do if item.group == node then matched = item end end
			if matched ~= nil then
				if not seen[matched] then seen[matched] = true; table.insert(cabinets, matched) end
				break
			end
			node = pytha.get_element_parent_group(node)
		end
	end
	if #cabinets == 0 then
		pyui.alert(pyloc "None of the clicked parts belongs to a cabinet group.")
		return
	end
	local data = {count = #cabinets, mode = 1, index = 1, custom = ""}
	if pyui.run_modal_subdialog(tag_dialog, data) ~= "ok" then return end
	local tag = data.custom ~= "" and data.custom:upper() or HARDWARE[data.index]
	for _, item in ipairs(cabinets) do
		local tags = read_tags(item.group)
		if data.mode == 3 then
			tags = {}
		elseif data.mode == 2 then
			tags = {tag}
		else
			local present = false
			for _, existing in ipairs(tags) do if existing == tag then present = true end end
			if not present then table.insert(tags, tag) end
		end
		pytha.set_element_history(item.group, {tags = tags}, TAG_KEY)
	end
	pyui.alert(string.format("%d cabinet(s) updated. Note: running Kitchen Wizard Edit rebuilds the kitchen and clears these tags (like the numbers).", #cabinets))
end


----------------------------------------------------------------------------------------------------------------
-- elevations, pared back: numbers on every cabinet, text only for hardware and spec'd items
----------------------------------------------------------------------------------------------------------------
local SPECD_TYPES = {sink = true, dishwasher = true, fridge = true, hob = true, hob_and_oven = true, hood = true,
	high_appliance1 = true, high_appliance2 = true, high_fridge = true}

local function handle_name(handle)
	if handle == nil then return nil end
	local call_ok, name_value = pcall(function() return handle:get_name() end)
	if call_ok and name_value ~= nil and tostring(name_value) ~= "" then
		return (tostring(name_value):gsub("%.[Pp][Yy][Oo][Xx]?$", ""))
	end
	return nil
end

-- the lines shown under a cabinet in the elevation: spec'd item (and its model if readable), then each hardware tag. Empty for a plain cabinet.
local function elevation_lines(item)
	local lines = {}
	local spec = item.spec
	if spec ~= nil and SPECD_TYPES[spec.this_type or ""] then
		table.insert(lines, TYPE_CODES[spec.this_type])
		local first_model = handle_name(spec.appliance_file)
		if first_model ~= nil then table.insert(lines, first_model) end
		if spec.this_type ~= "sink" then
			local second_model = handle_name(spec.appliance_file2)
			if second_model ~= nil and second_model ~= first_model then table.insert(lines, second_model) end
		end
	end
	for _, tag in ipairs(read_tags(item.group)) do table.insert(lines, tag) end
	return lines
end

-- PYTHA's plan-sheet views look from the front (xz, looking +y: the back wall) and from the right (yz, looking -x: the left wall).
-- In both, the model axis that runs to the viewer's right is +x / +y. Other runs would need a rear or left view, which is not drawn.
local ELEVATION_VIEWS = {[90] = {name = "BACK WALL", view = "xz", h_axis = 1}, [0] = {name = "LEFT WALL", view = "yz", h_axis = 2}}

local function build_elevations(items, settings)
	local paper = PAPERS[tostring(settings.paper):lower():gsub("[%s%-_]", "")] or PAPERS.archd
	local area, ts = paper.area, paper.text_scale
	local runs, order, skipped_runs = {}, {}, {}
	for _, item in ipairs(items) do
		local definition = ELEVATION_VIEWS[item.run]
		if definition == nil then
			skipped_runs[item.run_label] = true
		else
			if runs[item.run] == nil then runs[item.run] = {definition = definition, list = {}}; table.insert(order, item.run) end
			table.insert(runs[item.run].list, item)
		end
	end
	if #order == 0 then error("no run faces the back wall or the left wall: nothing to draw (the other views are not available)") end
	table.sort(order, function(a, b) return a > b end)		--back wall first
	for _, run in ipairs(order) do
		local entry = runs[run]
		local low, high = math.huge, -math.huge
		local z_low, z_high = math.huge, -math.huge
		for _, item in ipairs(entry.list) do
			local h = entry.definition.h_axis
			low = math.min(low, item.box[1][h], item.box[2][h]); high = math.max(high, item.box[1][h], item.box[2][h])
			z_low = math.min(z_low, item.box[1][3], item.box[2][3]); z_high = math.max(z_high, item.box[1][3], item.box[2][3])
		end
		entry.h_low, entry.h_high, entry.z_low, entry.z_high = low, high, math.min(0, z_low), z_high
		entry.width_in, entry.height_in = math.max(1, doc_to_in(high - low)), math.max(1, doc_to_in(z_high - entry.z_low))
	end
	local max_width, total_height = 0, 0
	for _, run in ipairs(order) do
		max_width = math.max(max_width, runs[run].width_in)
		total_height = total_height + runs[run].height_in
	end
	local label_band_sheet = 1.1 * ts + 0.9				--sheet inches for the title, gap and label rows per run
	local fit_ratio = math.min(area.width / max_width, (area.height - #order * label_band_sheet) / total_height)
	local scale_entry, fits = pick_scale(fit_ratio, parse_inches_per_foot(settings.scale))
	local ratio = 12 / scale_entry.inches_per_foot
	local sheet, used_name = new_sheet(settings.sheet_name)
	local y_top = area.top + area.height
	local number_mm, text_mm = 3.2 * ts, 2.1 * ts
	local labelled, numbered = 0, 0
	for _, run in ipairs(order) do
		local entry = runs[run]
		local w_in, h_in = entry.width_in / ratio, entry.height_in / ratio
		local cx = area.left + w_in / 2 + (area.width - w_in) / 2 * 0		--left aligned
		sheet_text(sheet, entry.definition.name, area.left, y_top, 4.2 * ts, true)
		local view_top = y_top - 0.45 * ts
		local cy = view_top - h_in / 2
		local centre_h = (entry.h_low + entry.h_high) / 2
		local centre_v = (entry.z_low + entry.z_high) / 2
		local groups = {}
		for _, item in ipairs(entry.list) do table.insert(groups, item.group) end
		local frame_w = 2 * (math.abs(centre_h / ratio) + to_doc_from_in(w_in) / 2) + 0.2
		local frame_h = 2 * (math.abs(centre_v / ratio) + to_doc_from_in(h_in) / 2) + 0.2
		pyplot.insert_detail(sheet, {view = entry.definition.view, position = {to_doc_from_in(cx) - centre_h / ratio, to_doc_from_in(cy) - centre_v / ratio},
			size = {frame_w, frame_h}, scale = ratio}, groups)
		-- label row under the view: number for every cabinet, text only for hardware and spec'd items
		local label_top = view_top - h_in - 0.12 * ts
		local deepest = 0
		local row_top = label_top
		for pass = 1, 2 do		--pass 1 bases and talls, pass 2 uppers on their own row so labels never collide
		label_top = row_top
		local pass_deepest = 0
		for _, item in ipairs(entry.list) do
			if (item.tier == 2) == (pass == 2) then
			local h = entry.definition.h_axis
			local item_centre = (item.box[1][h] + item.box[2][h]) / 2
			local item_width_in = doc_to_in(math.abs(item.box[2][h] - item.box[1][h])) / ratio
			local x_in = cx + doc_to_in(item_centre - centre_h) / ratio
			local number_text = item.number and tostring(item.number) or "-"
			if item.tier == 2 then number_text = "(" .. number_text .. ")" end
			sheet_text(sheet, number_text, x_in - #number_text * char_width_in(number_mm) / 2, label_top, number_mm, true)
			numbered = numbered + 1
			local y_in = label_top - number_mm / 25.4 * 1.3
			local lines = elevation_lines(item)
			local size = text_mm
			local wrapped = {}
			for _, line in ipairs(lines) do
				local current = ""
				local max_chars = math.max(4, math.floor(item_width_in / char_width_in(size)))
				for word in line:gmatch("%S+") do
					if current == "" then current = word
					elseif #current + 1 + #word <= max_chars then current = current .. " " .. word
					else table.insert(wrapped, current); current = word end
				end
				if current ~= "" then table.insert(wrapped, current) end
			end
			for _, line in ipairs(wrapped) do
				sheet_text(sheet, line, x_in - #line * char_width_in(size) / 2, y_in, size, false)
				y_in = y_in - size / 25.4 * 1.25
			end
			if #wrapped > 0 then labelled = labelled + 1 end
			pass_deepest = math.max(pass_deepest, label_top - y_in)
			end
		end
		deepest = deepest + pass_deepest + (pass_deepest > 0 and 0.3 * ts or 0)
		row_top = label_top - pass_deepest - 0.3 * ts
		end
		label_top = row_top
		y_top = view_top - h_in - 0.12 * ts - math.max(deepest, 0.7 * ts) - 0.3 * ts
	end
	local title_y = area.top - 0.35 * ts
	sheet_text(sheet, settings.title, area.left, title_y, 6 * ts, true)
	sheet_text(sheet, settings.number, area.left + area.width - 1.7 * ts, title_y, 9 * ts, true)
	local date = ""
	pcall(function() date = os.date("%Y-%m-%d") end)
	sheet_text(sheet, "Scale " .. scale_entry.name .. "\" = 1'-0\"   " .. date, area.left, title_y - 0.4 * ts, 3 * ts, false)
	local skipped_list = {}
	for label in pairs(skipped_runs) do table.insert(skipped_list, label) end
	table.sort(skipped_list)
	return {name = used_name, scale = scale_entry.name, fits = fits, numbered = numbered, labelled = labelled, runs = #order, skipped = skipped_list,
		overflow = y_top < area.top - 0.2}
end

local function elevation_dialog(dialog, settings)
	dialog:set_window_title(pyloc "Plan Callouts - Elevations")
	dialog:create_standalone_label({1, 2}, pyloc "Numbers on every cabinet; text only for hardware and spec'd items.")
	dialog:create_label(1, pyloc "Sheet name")
	local sheet_name = dialog:create_text_box(2, settings.sheet_name)
	sheet_name:set_on_change_handler(function(text) if text ~= "" then settings.sheet_name = text end end)
	dialog:create_label(1, pyloc "Title")
	local title = dialog:create_text_box(2, settings.title)
	title:set_on_change_handler(function(text) settings.title = text end)
	dialog:create_label(1, pyloc "Sheet number")
	local number = dialog:create_text_box(2, settings.number)
	number:set_on_change_handler(function(text) settings.number = text end)
	dialog:create_label(1, pyloc "Paper (archd or letter)")
	local paper = dialog:create_text_box(2, settings.paper)
	paper:set_on_change_handler(function(text) settings.paper = text end)
	dialog:create_label(1, pyloc "Scale, inches per foot (blank = auto)")
	local scale = dialog:create_text_box(2, settings.scale)
	scale:set_on_change_handler(function(text) settings.scale = text end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

function plan_elevations()
	local settings = {sheet_name = "Cabinet Elevations", title = "CABINET ELEVATIONS", number = "A-201", paper = "archd", scale = ""}
	local loaded = pyio.load_values("plan_elevations_settings")
	if type(loaded) == "table" then
		for key, value in pairs(loaded) do
			if settings[key] ~= nil and type(value) == type(settings[key]) then settings[key] = value end
		end
	end
	if pyui.run_modal_subdialog(elevation_dialog, settings) ~= "ok" then return end
	pyio.save_values("plan_elevations_settings", settings)
	local items = collect()
	if #items == 0 then
		pyui.alert(pyloc "No cabinets or groups found (loose parts outside a group are not scanned).")
		return
	end
	local ok, result = pcall(build_elevations, items, settings)
	if not ok then
		pyui.alert(pyloc "Could not build the elevations:" .. "\n" .. tostring(result))
		return
	end
	local notes = {string.format("Sheet '%s' made at %s\" = 1'-0\": %d run(s), %d cabinets numbered, %d with hardware or spec'd text.", result.name, result.scale, result.runs, result.numbered, result.labelled)}
	if not result.fits then table.insert(notes, "The typed scale is too big for the sheet: the views will run past the frame.") end
	if result.overflow then table.insert(notes, "The runs together are taller than the drawing area: use a smaller scale or two sheets.") end
	if #result.skipped > 0 then table.insert(notes, "Not drawn (PYTHA's sheet views only look from the front and the right): " .. table.concat(result.skipped, ", ") .. ".") end
	pyui.alert(table.concat(notes, "\n"))
end


----------------------------------------------------------------------------------------------------------------
-- per-cabinet sections: a side cut through every spec'd / hardware cabinet; the section objects also draw cut lines on plan and elevation sheets
----------------------------------------------------------------------------------------------------------------
local made_sections = {}		--handles made in this session (handles cannot be listed later, so a restart forgets them)

local function section_label(item)
	local number_text = item.number and tostring(item.number) or "-"
	local lines = elevation_lines(item)
	return number_text, lines
end

local function build_sections(items, settings)
	local targets = {}
	for _, item in ipairs(items) do
		if settings.all_cabinets or #elevation_lines(item) > 0 then table.insert(targets, item) end
	end
	if #targets == 0 then error("no spec'd or hardware-tagged cabinets found (tag some with 'Tag hardware', or tick 'every cabinet')") end
	local paper = PAPERS[tostring(settings.paper):lower():gsub("[%s%-_]", "")] or PAPERS.archd
	local area, ts = paper.area, paper.text_scale
	local mode = tostring(settings.mode):lower()
	if mode ~= "side" and mode ~= "elevation" then mode = "both" end
	-- one cut = {item, kind}. run_axis = model axis the run extends along; side cuts are perpendicular to it, elevation cuts parallel to it (through mid-depth)
	local cuts = {}
	local max_w, max_height = 1, 1
	for _, item in ipairs(targets) do
		item.run_axis = (item.run == 0 or item.run == 180) and 2 or 1
		local depth_axis = (item.run_axis == 1) and 2 or 1
		local depth_in = doc_to_in(math.abs(item.box[2][depth_axis] - item.box[1][depth_axis]))
		local width_in = doc_to_in(math.abs(item.box[2][item.run_axis] - item.box[1][item.run_axis]))
		local height_in = doc_to_in(math.abs(item.box[2][3] - item.box[1][3]))
		max_height = math.max(max_height, height_in)
		if mode ~= "elevation" then
			table.insert(cuts, {item = item, kind = "side", w_in = depth_in, h_in = height_in, tag = "S"})
			max_w = math.max(max_w, depth_in)
		end
		if mode ~= "side" then
			table.insert(cuts, {item = item, kind = "elevation", w_in = width_in, h_in = height_in, tag = "E"})
			max_w = math.max(max_w, width_in)
		end
	end
	local label_band = 2.4 * ts					--sheet inches under each section for number and text
	local gap = 0.6 * ts
	-- try scales from big to small until the grid of cells fits the drawing area
	local chosen, columns_used, rows_used, cell_w, cell_h
	local scale_options = {}
	if settings.scale ~= "" and parse_inches_per_foot(settings.scale) then scale_options = {parse_inches_per_foot(settings.scale)} end
	if #scale_options == 0 then
		for index = #SCALES, 1, -1 do table.insert(scale_options, SCALES[index].inches_per_foot) end
	end
	for _, per_foot in ipairs(scale_options) do
		local ratio = 12 / per_foot
		local w, h = max_w / ratio + gap, max_height / ratio + label_band + gap
		local columns = math.max(1, math.floor(area.width / w))
		local rows = math.ceil(#cuts / columns)
		chosen, cell_w, cell_h, columns_used, rows_used = per_foot, w, h, columns, rows
		if rows * h <= area.height then break end
	end
	local ratio = 12 / chosen
	local fits = rows_used * cell_h <= area.height
	local sheet, used_name = new_sheet(settings.sheet_name)
	local top = area.top + area.height
	local made = 0
	for index, cut in ipairs(cuts) do
		local item = cut.item
		local column, row = (index - 1) % columns_used, math.floor((index - 1) / columns_used)
		local x0 = area.left + column * cell_w
		local y0 = top - row * cell_h
		local number_text, lines = section_label(item)
		local centre_x = (item.box[1][1] + item.box[2][1]) / 2
		local centre_y = (item.box[1][2] + item.box[2][2]) / 2
		-- side: plane perpendicular to the run axis. elevation: plane perpendicular to the depth axis
		local plane_axis = (cut.kind == "side") and item.run_axis or ((item.run_axis == 1) and 2 or 1)
		local plane = (plane_axis == 1) and "yz" or "xz"
		local section_name = "CAB " .. number_text .. " " .. cut.tag
		local section_ok, section = pcall(function()
			return pytha.create_section(item.group, {plane = plane, position = {centre_x, centre_y, 0}, name = section_name})
		end)
		if section_ok and section ~= nil then
			table.insert(made_sections, section)
			local w_in, h_in = cut.w_in / ratio, cut.h_in / ratio
			pyplot.insert_section(sheet, section, {position = {to_doc_from_in(x0 + cell_w / 2), to_doc_from_in(y0 - h_in / 2 - 0.2 * ts)},
				size = {to_doc_from_in(w_in), to_doc_from_in(h_in)}, scale = ratio, graphic_flags = {"edges", "solid", "hatching"}})
			made = made + 1
		end
		local text_top = y0 - max_height / ratio - 0.5 * ts
		local heading = (cut.kind == "side") and ("SECTION " .. number_text .. "-S  (SIDE)") or ("SECTION " .. number_text .. "-E  (ELEVATION)")
		sheet_text(sheet, heading, x0, text_top, 3.4 * ts, true)
		local line_y = text_top - 3.4 * ts / 25.4 * 1.4
		for _, line in ipairs(lines) do
			sheet_text(sheet, line, x0, line_y, 2.2 * ts, false)
			line_y = line_y - 2.2 * ts / 25.4 * 1.3
		end
	end
	local title_y = area.top - 0.35 * ts
	sheet_text(sheet, settings.title, area.left, title_y, 6 * ts, true)
	sheet_text(sheet, settings.number, area.left + area.width - 1.7 * ts, title_y, 9 * ts, true)
	local date = ""
	pcall(function() date = os.date("%Y-%m-%d") end)
	sheet_text(sheet, "Scale " .. string.format("%g", chosen) .. "\" = 1'-0\"   " .. date, area.left, title_y - 0.4 * ts, 3 * ts, false)
	return {name = used_name, count = made, targets = #cuts, scale = chosen, fits = fits}
end

local function section_dialog(dialog, settings)
	dialog:set_window_title(pyloc "Plan Callouts - Sections")
	dialog:create_standalone_label({1, 2}, pyloc "Side and/or elevation cuts through each spec'd or hardware cabinet.")
	dialog:create_label(1, pyloc "Sheet name")
	local sheet_name = dialog:create_text_box(2, settings.sheet_name)
	sheet_name:set_on_change_handler(function(text) if text ~= "" then settings.sheet_name = text end end)
	dialog:create_label(1, pyloc "Title")
	local title = dialog:create_text_box(2, settings.title)
	title:set_on_change_handler(function(text) settings.title = text end)
	dialog:create_label(1, pyloc "Sheet number")
	local number = dialog:create_text_box(2, settings.number)
	number:set_on_change_handler(function(text) settings.number = text end)
	dialog:create_label(1, pyloc "Paper (archd or letter)")
	local paper = dialog:create_text_box(2, settings.paper)
	paper:set_on_change_handler(function(text) settings.paper = text end)
	dialog:create_label(1, pyloc "Scale, inches per foot (blank = auto)")
	local scale = dialog:create_text_box(2, settings.scale)
	scale:set_on_change_handler(function(text) settings.scale = text end)
	dialog:create_label(1, pyloc "Cuts (side, elevation or both)")
	local mode = dialog:create_text_box(2, settings.mode)
	mode:set_on_change_handler(function(text) settings.mode = text end)
	local all = dialog:create_check_box({1, 2}, pyloc "Every cabinet, not just spec'd and hardware", settings.all_cabinets)
	all:set_on_change_handler(function(state) settings.all_cabinets = state end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

function plan_sections()
	local settings = {sheet_name = "Cabinet Sections", title = "CABINET SECTIONS", number = "A-301", paper = "archd", scale = "", all_cabinets = false, mode = "both"}
	local loaded = pyio.load_values("plan_sections_settings")
	if type(loaded) == "table" then
		for key, value in pairs(loaded) do
			if settings[key] ~= nil and type(value) == type(settings[key]) then settings[key] = value end
		end
	end
	if pyui.run_modal_subdialog(section_dialog, settings) ~= "ok" then return end
	pyio.save_values("plan_sections_settings", settings)
	local items = collect()
	if #items == 0 then
		pyui.alert(pyloc "No cabinets or groups found (loose parts outside a group are not scanned).")
		return
	end
	local ok, result = pcall(build_sections, items, settings)
	if not ok then
		pyui.alert(pyloc "Could not build the sections:" .. "\n" .. tostring(result))
		return
	end
	local notes = {string.format("Sheet '%s': %d of %d sections placed at %g\" = 1'-0\".", result.name, result.count, result.targets, result.scale),
		"The cut lines (CAB n) now show on every plan and elevation sheet, and stay in the model until you run 'Remove cabinet sections'."}
	if not result.fits then table.insert(notes, "The sections do not all fit at this scale: use a smaller scale or fewer cabinets.") end
	pyui.alert(table.concat(notes, "\n"))
end

function remove_cabinet_sections()
	if #made_sections == 0 then
		pyui.alert(pyloc "No sections from this session to remove. (After a restart, delete the old CAB n sections by hand.)")
		return
	end
	local removed = 0
	for _, section in ipairs(made_sections) do
		if pcall(function() pytha.delete_section(section) end) then removed = removed + 1 end
	end
	made_sections = {}
	pyui.alert(string.format("%d section(s) removed.", removed))
end

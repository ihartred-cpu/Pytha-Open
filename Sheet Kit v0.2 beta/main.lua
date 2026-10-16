-- Sheet Kit v0.2 BETA (2026-10-15) - lays out front / top / side views of the whole model on a NEW plot sheet,
-- with view labels and a title block (title, sheet number, scale, date). Built only from calls that Glyph Lab 0.5/0.6
-- showed working on PYTHA V26 (compiled 2026-07-20 14:19:45): pyplot.create_sheet / insert_detail / insert_text.
--
-- What Glyph Lab observed (by eye, Letter landscape sheet, inch document):
--   * insert_detail with view_min/view_max and NO scale: places and fits the view. Position = CENTRE of the view, document units.
--   * insert_text: position = TOP-LEFT of the text (it hangs down from y), document units; size is in MM.
--   * pydim (model dimensions/annotations) does not exist on this build; nothing here uses it.
-- NOT verified: top/side view orientation on a model with real depth (check the first sheet!), sheet sizes other than
-- Letter landscape (the layout constants below assume 11 x 8.5 in), non-inch documents.

local SHEET_W_IN, SHEET_H_IN = 11, 8.5
local AREA = {x0 = 0.7, y0 = 1.7, w = 9.6, h = 6.1}		--drawing area on the sheet, inches (above the title block)
local GAP_IN = 0.7											--space between views, inches
local SKIP_GROUPS = {["Group Numbers"] = true, ["Glyph Lab"] = true}
--US architectural scales: inches on the sheet per foot of model -> ratio = 12 / that. Smallest drawn scale is 1/2" = 1'-0".
local SCALES = {
	{ipf = 0.5, name = "1/2"}, {ipf = 0.75, name = "3/4"}, {ipf = 1, name = "1"}, {ipf = 1.5, name = "1-1/2"},
	{ipf = 3, name = "3"}, {ipf = 6, name = "6"}, {ipf = 12, name = "12"},
}

local DEFAULTS = {sheet_name = "Elevations", title = "ELEVATIONS", number = "A-101", scale = ""}		--scale: "" = auto, else inches per foot, e.g. 3/4 or 1-1/2

----------------------------------------------------------------------------------------------------------------
-- SheetKit: the reusable part (copy this block into another plugin; `require` between plugins is untested)
----------------------------------------------------------------------------------------------------------------
local SheetKit = {}

function SheetKit.to_doc(v_mm)							--mm -> document units
	if pytha.get_length_unit() == "in" then return v_mm / 25.4 end
	return v_mm
end
function SheetKit.in_to_doc(v_in) return SheetKit.to_doc(v_in * 25.4) end

--union bounding box {{x,y,z},{x,y,z}} of the top-level groups (or of `groups` if given), skipping helper groups
function SheetKit.model_bounds(groups, include_all)
	local lo, hi, n, skipped = nil, nil, 0, 0
	local function add(g)
		local ok, bb = pcall(function() return pytha.get_element_bounding_box(g) end)
		if not (ok and type(bb) == "table" and bb[1] and bb[2]) then return end
		n = n + 1
		lo = lo or {bb[1][1], bb[1][2], bb[1][3]}
		hi = hi or {bb[2][1], bb[2][2], bb[2][3]}
		for i = 1, 3 do
			lo[i] = math.min(lo[i], bb[1][i], bb[2][i])
			hi[i] = math.max(hi[i], bb[1][i], bb[2][i])
		end
	end
	if groups then
		for _, g in ipairs(groups) do add(g) end
	else
		for g in pytha.enumerate_groups() do
			if pytha.get_element_parent_group(g) == nil then
				local ok, nm = pcall(function() return tostring(pytha.get_element_attribute(g, 3)) end)
				if ok and SKIP_GROUPS[nm] and not include_all then skipped = skipped + 1 else add(g) end
			end
		end
	end
	if n == 0 then return nil, 0, skipped end
	return {lo, hi}, n, skipped
end

--place one orthographic view: centre (cx, cy) and size (w, h) in document units, clipped to the bounds box
--axes: h and v are the model axis indices (1=x, 2=y, 3=z) that run horizontally / vertically in that view
function SheetKit.place_view(sheet, view, bounds, h_axis, v_axis, cx, cy, w, h, elements)
	return pyplot.insert_detail(sheet, {
		view = view, position = {cx, cy}, size = {w, h},
		view_min = {bounds[1][h_axis], bounds[1][v_axis]},
		view_max = {bounds[2][h_axis], bounds[2][v_axis]},
	}, elements)
end

--text: x, y = TOP-LEFT in document units, size in mm
function SheetKit.text(sheet, str, x, y, size_mm, bold)
	return pyplot.insert_text(sheet, str, {size = size_mm, position = {x, y}, bold = bold or false, font = "Arial"})
end

--inches-per-foot text ("3/4", "1-1/2", "1", "3") -> number, or nil
function SheetKit.parse_ipf(text)
	text = tostring(text or ""):gsub("[%s\"']", ""):gsub("=1.*", "")
	if text == "" then return nil end
	local whole, num, den = text:match("^(%d+)%-(%d+)/(%d+)$")
	if whole then return tonumber(whole) + tonumber(num) / tonumber(den) end
	num, den = text:match("^(%d+)/(%d+)$")
	if num then return tonumber(num) / tonumber(den) end
	return tonumber(text)
end

function SheetKit.scale_label(sc)
	if sc.ipf >= 12 then return "FULL SIZE" end
	return sc.name .. "\" = 1'-0\""
end

--auto: the largest listed scale whose views still fit (k_fit = largest sheet/model ratio that fits).
--typed: the listed scale closest to what was typed. Returns scale entry and whether the views fit the drawing area.
function SheetKit.pick_scale(k_fit, typed_ipf)
	local want = typed_ipf
	if want == nil then
		want = SCALES[1].ipf
		for _, sc in ipairs(SCALES) do
			if sc.ipf / 12 <= k_fit then want = sc.ipf end
		end
	end
	local best = SCALES[1]
	for _, sc in ipairs(SCALES) do
		if math.abs(sc.ipf - want) < math.abs(best.ipf - want) then best = sc end
	end
	return best, best.ipf / 12 <= k_fit * 1.0001
end

function SheetKit.new_sheet(name)
	local ok, sh = pcall(function() return pyplot.create_sheet(name) end)
	if ok then return sh, name end
	for i = 2, 9 do
		local nm = name .. " " .. i
		local ok2, sh2 = pcall(function() return pyplot.create_sheet(nm) end)
		if ok2 then return sh2, nm end
	end
	error("could not create a sheet named '" .. name .. "': " .. tostring(sh))
end

--the whole layout: third-angle (top above front, side to the right of front), one common scale, labels, title block
function SheetKit.elevations_sheet(opts)
	local bounds, n, skipped = SheetKit.model_bounds()
	if not bounds and skipped > 0 then bounds, n = SheetKit.model_bounds(nil, true) end		--only helper groups exist: draw them
	if not bounds then error("no top-level groups found to draw (loose parts outside a group are not scanned; put them in a group)") end
	local u = SheetKit.to_doc(1)							--document units per mm
	local function span_mm(i) return math.max(1, math.abs(bounds[2][i] - bounds[1][i]) / u) end
	local wF, hF = span_mm(1), span_mm(3)					--front: x by z
	local dT = span_mm(2)									--top: x by y
	local wS = dT											--side: y by z
	local k_fit = math.min((AREA.w - GAP_IN) * 25.4 / (wF + wS), (AREA.h - GAP_IN) * 25.4 / (hF + dT))
	local sc, fits = SheetKit.pick_scale(k_fit, SheetKit.parse_ipf(opts.scale))
	local ratio = 12 / sc.ipf
	local k = 1 / ratio
	local function inch(mm_) return mm_ * k / 25.4 end		--model mm -> sheet inches
	local wFs, hFs, wSs, hTs = inch(wF), inch(hF), inch(wS), inch(dT)
	local aw, ah = wFs + GAP_IN + wSs, hFs + GAP_IN + hTs
	local ox = AREA.x0 + (AREA.w - aw) / 2
	local oy = AREA.y0 + (AREA.h - ah) / 2
	local D = SheetKit.in_to_doc
	local sheet, used_name = SheetKit.new_sheet(opts.sheet_name)
	local placed = {}
	local function put(label, view, ha, va, cx, cy, w, h)
		SheetKit.place_view(sheet, view, bounds, ha, va, D(cx), D(cy), D(w), D(h))
		SheetKit.text(sheet, label, D(cx - w / 2), D(cy - h / 2 - 0.1), 4, true)		--hangs down from just below the view
		table.insert(placed, label)
	end
	put("FRONT", "xz", 1, 3, ox + wFs / 2, oy + hFs / 2, wFs, hFs)
	put("TOP", "xy", 1, 2, ox + wFs / 2, oy + hFs + GAP_IN + hTs / 2, wFs, hTs)
	put("SIDE", "yz", 2, 3, ox + wFs + GAP_IN + wSs / 2, oy + hFs / 2, wSs, hFs)
	local date = ""
	pcall(function() date = os.date("%Y-%m-%d") end)
	SheetKit.text(sheet, opts.title, D(0.7), D(1.35), 6, true)
	SheetKit.text(sheet, opts.number, D(8.6), D(1.35), 9, true)
	SheetKit.text(sheet, "Scale " .. SheetKit.scale_label(sc) .. "   " .. date, D(0.7), D(0.95), 3, false)
	return {sheet = sheet, name = used_name, scale = SheetKit.scale_label(sc), fits = fits, groups = n, views = placed}
end

----------------------------------------------------------------------------------------------------------------
-- plugin entry
----------------------------------------------------------------------------------------------------------------
local function dialog_fn(dialog, s)
	dialog:set_window_title(pyloc "Sheet Kit 0.2 (beta)")
	dialog:create_standalone_label({1, 2}, pyloc "Makes a new plot sheet with front, top and side views of the whole model, view labels and a title block.")
	dialog:create_label(1, pyloc "Sheet name")
	local nm = dialog:create_text_box(2, s.sheet_name)
	nm:set_on_change_handler(function(text) if text ~= "" then s.sheet_name = text end end)
	dialog:create_label(1, pyloc "Title")
	local ti = dialog:create_text_box(2, s.title)
	ti:set_on_change_handler(function(text) s.title = text end)
	dialog:create_label(1, pyloc "Sheet number")
	local nu = dialog:create_text_box(2, s.number)
	nu:set_on_change_handler(function(text) s.number = text end)
	dialog:create_label(1, pyloc "Scale, inches per foot (blank = auto)")
	local sc = dialog:create_text_box(2, s.scale)
	sc:set_on_change_handler(function(text) s.scale = text end)
	dialog:create_ok_button(1)
	dialog:create_cancel_button(2)
	dialog:equalize_column_widths({1, 2})
end

function sheet_kit()
	local s = {}
	for k, v in pairs(DEFAULTS) do s[k] = v end
	local ok_load, saved = pcall(function() return pyio.load_values("sheet_kit_settings") end)
	if ok_load and type(saved) == "table" then
		for k, v in pairs(saved) do
			if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then s[k] = v end
		end
	end
	if pyui.run_modal_subdialog(dialog_fn, s) ~= "ok" then return end
	pcall(function() pyio.save_values("sheet_kit_settings", s) end)
	local ok, res = pcall(SheetKit.elevations_sheet, s)
	if not ok then
		pyui.alert("Sheet Kit stopped: " .. tostring(res))
		return
	end
	pyui.alert(string.format("Sheet '%s' made from %d top-level group(s), scale %s.\nViews: %s.%s",
		res.name, res.groups, res.scale, table.concat(res.views, ", "),
		res.fits and "" or "\n\nWARNING: the views do not fit the drawing area at this scale and will overlap or run past the frame. Use a smaller scale, or leave the scale blank for auto (smallest offered is 1/2\" = 1'-0\")."))
end

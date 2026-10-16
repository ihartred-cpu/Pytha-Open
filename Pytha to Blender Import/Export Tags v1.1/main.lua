-- BCW Export Tags v1.1
-- PYTHA's glTF export keeps part names but drops layers and pens. "Export tags" is one
-- toggle: if no part carries a tag it appends " {L<layer>:<layer name> P<pen>}" to every part
-- name; if parts are already tagged it removes the tags again (names go back exactly as they
-- were). The PYTHA glTF Importer in Blender reads the tag back and builds Layer collections.
-- Workflow: run once (tag), export glTF, run again (untag).

local TAG_PATTERN = "%s*{L%-?%d+:.-%sP%-?%d+}%s*$"

local function strip_tag(name)
	return (string.gsub(name or "", TAG_PATTERN, ""))
end

-- attribute by name, falling back to its numeric ID (PYTHA attribute table: layer 1064,
-- layer_name 2064, pen 62, name 3)
local function attr(part, key, id)
	local v = pytha.get_element_attribute(part, key)
	if v == nil or v == "" then
		v = pytha.get_element_attribute(part, id)
	end
	return v
end

local function count_tagged()
	local n = 0
	for part in pytha.enumerate_parts() do
		local name = attr(part, "name", 3) or ""
		if strip_tag(name) ~= name then
			n = n + 1
		end
	end
	return n
end

local function tag_parts()
	local tagged, skipped = 0, 0
	for part in pytha.enumerate_parts() do
		local name = strip_tag(attr(part, "name", 3))
		local layer = tonumber(attr(part, "layer", 1064))
		local pen = tonumber(attr(part, "pen", 62))
		if layer ~= nil and pen ~= nil then
			local layer_name = attr(part, "layer_name", 2064) or ""
			layer_name = string.gsub(layer_name, "[{}]", "")
			pytha.set_element_name(part, name .. " {L" .. math.floor(layer) .. ":" .. layer_name .. " P" .. math.floor(pen) .. "}")
			tagged = tagged + 1
		else
			skipped = skipped + 1
		end
	end
	local msg = pyloc "Tagged parts: " .. tagged
	if skipped > 0 then
		msg = msg .. "\n" .. pyloc "Skipped (layer or pen not readable): " .. skipped
	end
	pyui.alert(msg .. "\n\n" .. pyloc "Export glTF now, then run Export tags again to remove the tags.")
end

local function untag_parts()
	local cleaned = 0
	for part in pytha.enumerate_parts() do
		local name = attr(part, "name", 3) or ""
		local stripped = strip_tag(name)
		if stripped ~= name then
			pytha.set_element_name(part, stripped)
			cleaned = cleaned + 1
		end
	end
	pyui.alert(pyloc "Tags removed from parts: " .. cleaned .. "\n\n" .. pyloc "Part names are back to normal.")
end

function export_tags()
	if count_tagged() > 0 then
		untag_parts()
	else
		tag_parts()
	end
end

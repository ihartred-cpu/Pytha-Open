-- BCW Export Tags v1.1
-- PYTHA's glTF export keeps part names but drops layers and pens. "Export tags" is one
-- toggle: if no part carries a tag it appends " {L<layer>:<layer name> P<pen>}" to every part
-- name; if parts are already tagged it removes the tags again (names go back exactly as they
-- were). The PYTHA glTF Importer in Blender reads the tag back and builds Layer collections.
-- Workflow: run once (tag), export glTF, run again (untag).
-- Names are read back after every rename; parts PYTHA refuses to rename are counted in the summary.

local TAG_PATTERN = "%s*{L%-?%d+:.-%sP%-?%d+}%s*$"

local function strip_tag(name)
	return (string.gsub(name or "", TAG_PATTERN, ""))
end

-- attribute by name, falling back to its numeric ID (PYTHA attribute table: layer 1064,
-- layer_name 2064, pen 62, name 3)
local function read_attribute(part, attribute_name, attribute_id)
	local value = pytha.get_element_attribute(part, attribute_name)
	if value == nil or value == "" then
		value = pytha.get_element_attribute(part, attribute_id)
	end
	return value
end

--set a part's name and read it back: set_element_name can do nothing without raising an error
local function set_name(part, name)
	pcall(pytha.set_element_name, part, name)
	if (read_attribute(part, "name", 3) or "") == name then return true end
	pcall(pytha.set_element_attributes, part, {[3] = name})
	return (read_attribute(part, "name", 3) or "") == name
end

local function has_tagged()
	for part in pytha.enumerate_parts() do
		local name = read_attribute(part, "name", 3) or ""
		if strip_tag(name) ~= name then
			return true
		end
	end
	return false
end

local function tag_parts()
	local tagged, skipped, failed = 0, 0, 0
	for part in pytha.enumerate_parts() do
		local name = strip_tag(read_attribute(part, "name", 3))
		local layer = tonumber(read_attribute(part, "layer", 1064))
		local pen = tonumber(read_attribute(part, "pen", 62))
		if layer ~= nil and pen ~= nil then
			local layer_name = read_attribute(part, "layer_name", 2064) or ""
			layer_name = string.gsub(layer_name, "[{}]", "")
			if set_name(part, name .. " {L" .. math.floor(layer) .. ":" .. layer_name .. " P" .. math.floor(pen) .. "}") then
				tagged = tagged + 1
			else
				failed = failed + 1
			end
		else
			skipped = skipped + 1
		end
	end
	local message = pyloc "Tagged parts: " .. tagged
	if skipped > 0 then
		message = message .. "\n" .. pyloc "Skipped (layer or pen not readable): " .. skipped
	end
	if failed > 0 then
		message = message .. "\n" .. pyloc "Name did not change (PYTHA ignored the rename): " .. failed
	end
	pyui.alert(message .. "\n\n" .. pyloc "Export glTF now, then run Export tags again to remove the tags.")
end

local function untag_parts()
	local cleaned, failed = 0, 0
	for part in pytha.enumerate_parts() do
		local name = read_attribute(part, "name", 3) or ""
		local stripped = strip_tag(name)
		if stripped ~= name then
			if set_name(part, stripped) then
				cleaned = cleaned + 1
			else
				failed = failed + 1
			end
		end
	end
	local message = pyloc "Tags removed from parts: " .. cleaned
	if failed > 0 then
		message = message .. "\n" .. pyloc "Still tagged (PYTHA ignored the rename): " .. failed .. "\n\n" .. pyloc "Run Export tags again to retry."
	else
		message = message .. "\n\n" .. pyloc "Part names are back to normal."
	end
	pyui.alert(message)
end

function export_tags()
	if has_tagged() then
		untag_parts()
	else
		tag_parts()
	end
end

-- BCW Export Tags v1.1
--
-- WHY THIS PLUGIN EXISTS
-- PYTHA's own glTF/GLB export keeps each part's NAME, but it throws away the part's
-- LAYER and PEN (PYTHA's "which colour/line-style is this on" attribute). The PYTHA
-- glTF Importer plugin for Blender (see Pytha to Blender Import/) wants that layer and
-- pen information so it can rebuild "Layers / <name>" and "Pens / Pen <n>" collections
-- in Blender. Since glTF has no field for layer/pen, this plugin smuggles the data
-- through in the one thing glTF *does* keep: the part's name.
--
-- HOW IT WORKS (one button, two states)
-- "Export tags" is a single toggle, not two separate buttons:
--   * If NO part currently has a tag, it TAGS every part: it appends text like
--     " {L12:Doors P3}" (layer number, layer name, pen number) to the end of the name.
--   * If parts ARE already tagged (because you ran it once already), it UNTAGS them:
--     it strips that " {L..:.. P..}" suffix back off, restoring the original name.
-- Suggested workflow: run once (tags the names) -> export glTF/GLB from PYTHA -> run
-- the plugin again (removes the tags, so your model's part names look normal again).
--
-- WHY READ-BACK AND COUNTING (v1.1 change from v1.0)
-- pytha.set_element_name() can silently do nothing on some parts (PYTHA may refuse to
-- rename certain elements). v1.0 just trusted the call; v1.1 always reads the name back
-- afterwards to confirm the rename actually happened, and reports how many parts were
-- tagged/untagged vs. skipped (missing layer or pen) vs. failed (PYTHA ignored the
-- rename) so you know whether a re-run is needed.

-- Matches the tag this plugin adds, e.g. " {L12:Doors P3}", anchored to the END of the
-- string ($) so it only ever touches a tag *we* appended, never text that happens to
-- look similar in the middle of a real part name.
--   %s*            optional whitespace before the tag
--   {L%-?%d+:      "{L" then an optional minus sign then digits then ":"  (the layer)
--   .-             the layer name, lazily matched (shortest possible match)
--   %sP%-?%d+}     a space, "P", an optional minus sign then digits, then "}" (the pen)
--   %s*$           optional trailing whitespace, then end of string
local TAG_PATTERN = "%s*{L%-?%d+:.-%sP%-?%d+}%s*$"

-- Remove our tag from a name, if present. string.gsub returns (new_string, count_of_
-- replacements); wrapping the call in parentheses keeps only the first value, which is
-- the cleaned name whether or not a tag was actually found.
local function strip_tag(name)
	return (string.gsub(name or "", TAG_PATTERN, ""))
end

-- Read a part attribute two ways: PYTHA lets you ask for an attribute either by its
-- friendly name ("layer") or by its raw numeric attribute ID (1064). Depending on the
-- PYTHA build/version, one of those can come back empty while the other works, so this
-- tries the name first and falls back to the ID.
-- Reference IDs used in this file: name = 3, layer = 1064, layer_name = 2064, pen = 62.
local function read_attribute(part, attribute_name, attribute_id)
	local value = pytha.get_element_attribute(part, attribute_name)
	if value == nil or value == "" then
		value = pytha.get_element_attribute(part, attribute_id)
	end
	return value
end

-- Rename a part and verify it actually took effect.
-- pcall() runs set_element_name() safely: if PYTHA raises an error for this part (e.g.
-- it's locked, or part of a protected group), pcall catches it instead of crashing the
-- whole plugin, and we just treat it as "didn't rename."
-- Even when no error is raised, PYTHA can still leave the old name in place, so we
-- always read the name back (via attribute 3, the raw "name" attribute) and compare.
-- If the normal rename didn't stick, we try one more time by writing attribute 3
-- directly with set_element_attributes - a lower-level call that occasionally succeeds
-- where set_element_name doesn't. Returns true only if the name is now correct.
local function set_name(part, name)
	pcall(pytha.set_element_name, part, name)
	if (read_attribute(part, "name", 3) or "") == name then return true end
	pcall(pytha.set_element_attributes, part, {[3] = name})
	return (read_attribute(part, "name", 3) or "") == name
end

-- Decide which mode to run in: look at every part and see if ANY of them already carry
-- a tag. If even one does, we assume a previous "tag" run happened and we should untag.
-- This is what makes "Export tags" a single toggle button instead of two.
local function has_tagged()
	for part in pytha.enumerate_parts() do
		local name = read_attribute(part, "name", 3) or ""
		if strip_tag(name) ~= name then
			return true
		end
	end
	return false
end

-- TAG MODE: walk every part in the model and append its layer/pen info to its name.
local function tag_parts()
	local tagged, skipped, failed = 0, 0, 0
	for part in pytha.enumerate_parts() do
		-- Strip any stray existing tag first, so re-running this never double-tags a part.
		local name = strip_tag(read_attribute(part, "name", 3))
		local layer = tonumber(read_attribute(part, "layer", 1064))
		local pen = tonumber(read_attribute(part, "pen", 62))
		if layer ~= nil and pen ~= nil then
			-- Layer names can themselves contain "{" or "}" (rare, but possible); strip
			-- those out so they can never be confused with our tag's own braces.
			local layer_name = read_attribute(part, "layer_name", 2064) or ""
			layer_name = string.gsub(layer_name, "[{}]", "")
			-- math.floor() because PYTHA numeric attributes often come back as floats
			-- like 12.0 - we want the tag to read "L12", not "L12.0".
			if set_name(part, name .. " {L" .. math.floor(layer) .. ":" .. layer_name .. " P" .. math.floor(pen) .. "}") then
				tagged = tagged + 1
			else
				failed = failed + 1
			end
		else
			-- No readable layer or pen (e.g. a part type PYTHA doesn't report them for):
			-- leave its name alone rather than writing a tag with missing data in it.
			skipped = skipped + 1
		end
	end
	-- pyloc "..." is PYTHA's translation function: it looks up the string in the
	-- plugin's config.base.xlf for the user's language, or falls back to the English
	-- text given here if no translation exists.
	local message = pyloc "Tagged parts: " .. tagged
	if skipped > 0 then
		message = message .. "\n" .. pyloc "Skipped (layer or pen not readable): " .. skipped
	end
	if failed > 0 then
		message = message .. "\n" .. pyloc "Name did not change (PYTHA ignored the rename): " .. failed
	end
	pyui.alert(message .. "\n\n" .. pyloc "Export glTF now, then run Export tags again to remove the tags.")
end

-- UNTAG MODE: walk every part and strip the tag back off, restoring the original name.
local function untag_parts()
	local cleaned, failed = 0, 0
	for part in pytha.enumerate_parts() do
		local name = read_attribute(part, "name", 3) or ""
		local stripped = strip_tag(name)
		if stripped ~= name then
			-- Only touch parts that actually have a tag; everything else is left alone.
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

-- Entry point PYTHA calls when the user clicks the plugin's single menu item (see
-- <entry-point>export_tags</entry-point> in config.xml). It must be a GLOBAL function
-- (no "local") so PYTHA's plugin loader can find it by name.
function export_tags()
	if has_tagged() then
		untag_parts()
	else
		tag_parts()
	end
end

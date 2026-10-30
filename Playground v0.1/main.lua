-- Playground v0.1 - small games that double as practice for the PYTHA Lua API (timer, dialog buttons, moving parts).
-- Facts it is built on (BCW Test Suite 24/25 on V26): timers only start from inside a dialog; a timer fires about 13 times a second, so
-- motion is paced by the wall clock where there is one; the animation argument is NOT elapsed seconds; arrow keys give no calls, so
-- every control is a dialog button; updating a label from a callback can fail now and then, so it is wrapped and done every few ticks.
-- Games are built far from the origin (x >= 5000 mm) and removed again when the dialog closes.
--
-- WHY THIS FILE EXISTS: it's a deliberately playful way to exercise the parts of PYTHA's Lua API that real tools
-- (like Group Numbering) also depend on - timers, modal dialogs with buttons instead of keyboard input, moving and
-- rotating elements every frame - without risking anything in a real cabinet file. Both games build their geometry
-- out at x >= 5000mm, well clear of a typical model, and remove every element they created the moment their dialog
-- closes, win or lose.

--millimetres -> the document's current length unit (every coordinate below is written in mm and converted at the call site)
local function mm(v)
	if pytha.get_length_unit() == "in" then return v / 25.4 end
	return v
end

--the real wall-clock second (os.time(), whole seconds), or nil if unavailable - used only to MEASURE how fast the
--timer is actually firing on this machine (see make_clock below), not to schedule anything
local function wall_clock()
	local call_ok, t = pcall(function() return os.time() end)
	if call_ok and type(t) == "number" then return t end
	return nil
end

--run fn(...) safely; return its result, or nil if it raised an error
local function try(fn, ...)
	local call_ok, result = pcall(fn, ...)
	if call_ok then return result end
	return nil
end

-- shared loop: one timer per game, one token kept, always stopped when the dialog closes
-- Wraps PYTHA's timer API (pyux.set_timer_handler / pyux.start_timer) into a
-- small "clock" object both games use identically: clock.start()/clock.stop()
-- toggle it on and off, and on_frame(clock) is called on every tick.
-- IMPORTANT: PYTHA's own timer interval (started with 0.05, i.e. "every 50ms"
-- /20 times a second) is only a REQUEST - the callback may actually fire
-- faster or slower depending on the machine and what else PYTHA is doing.
-- So rather than trust that request, the clock also measures its own real
-- firing rate using wall_clock() (counting how many ticks land inside one
-- real second) and stores that in clock.rate. Game code then scales motion
-- per tick by (expected_rate / clock.rate) - see on_frame in road_racer()
-- below - so the car/road speed looks the same on a fast or slow machine
-- instead of just being "however fast the timer happens to fire here".
local function make_clock(on_frame)
	local clock = {token = nil, running = false, ticks = 0, rate = 13, last_second = nil, ticks_this_second = 0}
	function clock.start()
		if clock.running then return end
		clock.running = true
		local token = pyux.set_timer_handler(function()
			if not clock.running then return end
			clock.ticks = clock.ticks + 1
			local now = wall_clock()
			if now ~= nil then			--measure real callbacks per second so game speed does not depend on the machine
				if clock.last_second == nil then clock.last_second = now end
				if now ~= clock.last_second then
					if clock.ticks_this_second > 2 then clock.rate = clock.ticks_this_second end
					clock.ticks_this_second, clock.last_second = 0, now
				end
				clock.ticks_this_second = clock.ticks_this_second + 1
			end
			on_frame(clock)
		end)
		clock.token = token
		pyux.start_timer(0.05, token)
	end
	function clock.stop()
		clock.running = false
		if clock.token ~= nil then try(function() pyux.set_timer_handler(nil, clock.token) end) end
		clock.token = nil
	end
	return clock
end

-- Set a dialog label's text, swallowing any error: per the header note,
-- updating a label from inside a timer callback can occasionally fail, and
-- that's not worth letting crash the game loop.
local function set_label(label, text)
	if label ~= nil then try(function() label:set_control_text(text) end) end
end

----------------------------------------------------------------------------------------------------------------
-- Road Racer: the car stays put, a big cylinder spins under it, obstacles ride on the cylinder, left/right buttons change lane
----------------------------------------------------------------------------------------------------------------
-- THE TRICK: rather than drive a car forward along an actual road (which
-- would need the model to keep growing), the car and camera stay still and
-- the ROAD ITSELF is a giant cylinder that spins underneath it, carrying the
-- lane marks and the obstacles around with it. "Driving forward" is just
-- rotating that cylinder; "changing lanes" is moving the car sideways a
-- fixed lane-width. Obstacles ride at a fixed angle on the cylinder and are
-- "hit" or "scored" purely by comparing their current angle against the
-- angle directly under the car (hit_degrees).
local ROAD = {radius = 11200, lanes = 8, lane_width = 200, count = 16, hit_degrees = 1.2, turn_scale = 0.125, car_turn = 0, cube_turn = 0, cx = 6000, cy = 5000, DIR = 1, keep_road = true, obstacle = "sphere", paint_car = true, road_turned = false}

-- import a .pyo (turned about z); returns one element (its top group) or nil
-- Loads an optional user-supplied .pyo model (car or obstacle), optionally
-- spinning it about z first (ROAD.car_turn/cube_turn let you correct a
-- model that was modelled facing the wrong way). `track`, if given, collects
-- every imported part/group handle so the caller can delete them all
-- individually later (see remove_all below - a single bad handle in a batch
-- delete can fail the whole batch, so this plugin always deletes one by one).
local function import_model(handle, turn, track)
	if handle == nil then return nil end
	local loaded = try(function() return pytha.import_pyo(handle) end)
	if type(loaded) ~= "table" or #loaded == 0 then return nil end
	local el = try(function() return pytha.get_element_common_group(loaded) end) or loaded
	-- remember every imported part (and the group) so the clean-up can delete each one on its own
	if track ~= nil then
		for _, part in ipairs(loaded) do table.insert(track, part) end
		if type(el) ~= "table" then table.insert(track, el) end
	end
	if turn ~= 0 then try(function() pytha.rotate_element(el, {0, 0, 0}, "z", turn) end) end
	return el
end

-- size of an element in mm {x, y}
local function model_size(el)
	local bb = try(function() return pytha.get_element_bounding_box(el) end)
	if type(bb) ~= "table" or bb[1] == nil or bb[2] == nil then return nil end
	local to_mm = (pytha.get_length_unit() == "in") and 25.4 or 1
	return {math.abs(bb[2][1] - bb[1][1]) * to_mm, math.abs(bb[2][2] - bb[1][2]) * to_mm}
end

-- stand an element on a point (bottom centre of its footprint)
-- Moves `el` so that its bounding box is centred over (x,y) and its lowest
-- point sits exactly at z - used to drop an imported .pyo model (whose own
-- origin could be anywhere) cleanly onto the road or a lane position.
local function stand_model(el, x, y, z)
	local bb = try(function() return pytha.get_element_bounding_box(el) end)
	if type(bb) ~= "table" or bb[1] == nil or bb[2] == nil then return end
	local mid_x, mid_y = (bb[1][1] + bb[2][1]) / 2, (bb[1][2] + bb[2][2]) / 2
	local bottom = math.min(bb[1][3], bb[2][3])
	try(function() pytha.move_element(el, {x - mid_x, y - mid_y, z - bottom}) end)
end

--import a model (if any) and stand it at (x,y,z); returns the element or nil
local function place_model(handle, x, y, z, turn, track)
	local el = import_model(handle, turn, track)
	if el ~= nil then stand_model(el, x, y, z) end
	return el
end

-- optional models for the car and the obstacles: any .pyo, picked once and remembered (handles survive a restart, T12)
local MODEL_STORE = "playground_models"

local function load_models()
	local loaded = try(function() return pyio.load_values(MODEL_STORE) end)
	if type(loaded) ~= "table" then loaded = {} end
	return loaded
end

local function save_models(models)
	try(function() pyio.save_values(MODEL_STORE, models) end)
end

-- materials: picked in the models dialog (pyux.select_material) and remembered. The road is given cylinder
-- projection and a tile size that closes around the circumference, the ball sphere projection.
local MATERIAL_STORE = "playground_materials"

-- two stores: one with the handles (may not be storable on every build) and one with just the names
local function load_materials()
	local loaded = try(function() return pyio.load_values(MATERIAL_STORE) end)
	if type(loaded) ~= "table" or next(loaded) == nil then
		loaded = try(function() return pyio.load_values(MATERIAL_STORE .. "_names") end)
		if type(loaded) ~= "table" then loaded = {} end
	end
	return loaded
end

local function save_materials(mats)
	local names = {}
	for key, value in pairs(mats) do if type(value) == "string" then names[key] = value end end
	try(function() pyio.save_values(MATERIAL_STORE .. "_names", names) end)
	try(function() pyio.save_values(MATERIAL_STORE, mats) end)
end

local function material_name(handle)
	return handle ~= nil and try(function() return pytha.get_element_name(handle) end) or nil
end

-- a stored handle may be stale after a restart: use it if it is still a material, else look the name up (V27)
-- A material HANDLE saved between PYTHA sessions can go stale (the session
-- it pointed to is gone). This checks the saved handle is still really a
-- material; if not, it falls back to the material's NAME (also saved) and
-- re-looks it up by name, refreshing the stored handle if found.
local function usable_material(mats, key)
	local handle = mats[key]
	if handle ~= nil and try(function() return pytha.get_element_type(handle) end) == "material" then return handle end
	local name = mats[key .. "_name"]
	if name ~= nil then
		local found = try(function() return pytha.find_material(name) end)
		if found ~= nil then mats[key] = found; return found end
	end
	return nil
end

--apply a material to one element, or to every element in a list (recursively)
local function apply_material(el, mat)
	if mat == nil or el == nil then return end
	if type(el) == "table" then for _, one in ipairs(el) do apply_material(one, mat) end return end
	try(function() pytha.set_element_material(el, mat) end)
end

-- Pre-game setup dialog: lets the player optionally pick a .pyo model for
-- the car and for the obstacles (otherwise plain boxes/spheres are used),
-- plus materials for the road/car/ball. Also offers a "Copy models to
-- scene" button so the player can drop plain boxes into the model, texture
-- them by hand in PYTHA, save that as a new .pyo, and pick THAT file next -
-- a round trip for building custom-textured game pieces without any
-- modelling tool beyond PYTHA itself.
local function setup_models()
	local models = load_models()
	local mats = load_materials()
	local car_label, cube_label
	local function describe(handle)
		if handle == nil then return "plain box" end
		return try(function() return handle:get_name() end) or "picked"
	end
	local function dialog(dlg)
		dlg:set_window_title("Road Racer - models")
		dlg:create_label({1, 2}, "Pick a .pyo for the car and for the obstacles, or leave plain boxes.")
		local pick_car = dlg:create_button(1, "Car .pyo...")
		local clear_car = dlg:create_button(2, "Car: plain box")
		car_label = dlg:create_label({1, 2}, "Car: " .. describe(models.car))
		local pick_cube = dlg:create_button(1, "Obstacle .pyo...")
		local clear_cube = dlg:create_button(2, "Obstacle: plain box")
		cube_label = dlg:create_label({1, 2}, "Obstacle: " .. describe(models.cube))
		pick_car:set_on_click_handler(function()
			local file = try(function() return pyux.select_pyo() end)
			if file ~= nil then models.car = file; set_label(car_label, "Car: " .. describe(file)) end
		end)
		clear_car:set_on_click_handler(function() models.car = nil; set_label(car_label, "Car: plain box") end)
		pick_cube:set_on_click_handler(function()
			local file = try(function() return pyux.select_pyo() end)
			if file ~= nil then models.cube = file; set_label(cube_label, "Obstacle: " .. describe(file)) end
		end)
		clear_cube:set_on_click_handler(function() models.cube = nil; set_label(cube_label, "Obstacle: plain box") end)
		local mat_labels = {}
		for _, item in ipairs({{"road", "Road"}, {"car", "Car"}, {"ball", "Ball"}}) do
			local key, title = item[1], item[2]
			local pick = dlg:create_button(1, title .. " material...")
			local clear = dlg:create_button(2, title .. ": none")
			local label = dlg:create_label({1, 2}, title .. " material: " .. (mats[key .. "_name"] or "none"))
			pick:set_on_click_handler(function()
				local chosen = try(function() return pyux.select_material() end)
				if chosen ~= nil then
					mats[key] = chosen
					mats[key .. "_name"] = material_name(chosen) or "picked"
					set_label(label, title .. " material: " .. mats[key .. "_name"])
				end
			end)
			clear:set_on_click_handler(function() mats[key] = nil; mats[key .. "_name"] = nil; set_label(label, title .. " material: none") end)
			mat_labels[key] = label
		end
		local drop = dlg:create_button(1, "Copy models to scene")
		drop:set_on_click_handler(function()
			local x = 2000
			for _, handle in ipairs({models.car, models.cube}) do
				if handle ~= nil then
					local el = import_model(handle, 0)
					if el ~= nil then stand_model(el, mm(x), mm(5000), 0); x = x + 3000 end
				end
			end
			models.dropped = true
			set_label(cube_label, "Copies placed at y=5000 (x=2000, 5000). Press OK, texture them, save as .pyo, pick the new file.")
		end)
		dlg:create_ok_button(1)
		dlg:create_cancel_button(2)
	end
	local result = pyui.run_modal_subdialog(dialog)
	if result ~= "ok" then return nil end
	local dropped = models.dropped
	models.dropped = nil
	save_models(models)
	save_materials(mats)
	if dropped then return nil end		-- the player just wanted to drop copies for texturing, not start the game
	models.materials = mats
	return models
end

-- delete handles one by one: a single stale or nested handle makes delete_element(list) fail as a whole,
-- and the try() around it then hides that nothing was deleted
local function remove_all(list)
	for _, el in ipairs(list) do
		if type(el) == "table" then remove_all(el)
		else try(function() pytha.delete_element(el) end) end
	end
end

-- the road cylinder is kept between runs (ROAD.keep_road) so it can be textured: only its length decides if it can be reused
local kept_road = nil		-- {el = cylinder, lane_w = lane width it was built for}

local function road_still_there()
	return kept_road ~= nil and try(function() return pytha.get_element_type(kept_road.el) end) ~= nil
end

-- THE GAME. Builds the road cylinder (or reuses the one from a previous run,
-- see kept_road above), scatters obstacles evenly around it, places the car,
-- then runs a timer loop (on_frame) that spins the cylinder a little every
-- tick, checks whether any obstacle has reached the car's angle (a "hit"),
-- counts obstacles that passed safely as score, and recycles each obstacle
-- to a new random lane once it has rotated out of view behind the car.
-- Everything built (road, marks, obstacles, car) is tracked in `made` and
-- `spawned` and deleted when the dialog closes, except the road itself if
-- ROAD.keep_road is true (so you can texture it between games).
local function road_racer()
	local models = setup_models()
	if models == nil then return end
	local R, lane_w, lanes = ROAD.radius, ROAD.lane_width, ROAD.lanes
	-- with a car model: lanes just wider than the car, and the crash window from the car's length
	local mats = models.materials or {}
	local road_mat, car_mat, ball_mat = usable_material(mats, "road"), usable_material(mats, "car"), usable_material(mats, "ball")
	local spawned = {}		-- every imported part, deleted one by one when the game closes
	local car_track = {}
	local car_el = import_model(models.car, ROAD.car_turn, car_track)
	for _, part in ipairs(car_track) do table.insert(spawned, part) end
	local hit_degrees = ROAD.hit_degrees
	local car_size = car_el and model_size(car_el)
	if car_size then
		lane_w = math.max(lane_w, math.ceil(car_size[1] * 1.25 / 50) * 50)
		hit_degrees = math.deg((car_size[2] / 2 + 150) / R)
	end
	local x0 = ROAD.cx - lanes * lane_w / 2
	local axis_point = {mm(ROAD.cx), mm(ROAD.cy), mm(R)}
	local made = {}
	local state = {lane = 4, score = 0, crashes = 0, rot = 0, speed = 4}
	-- the road: a cylinder lying along x. Reused from the last run when it is still in the model and the lane width
	-- has not changed, so a texture put on it stays; otherwise the old one is removed and a new one built
	local road
	if road_still_there() and kept_road.lane_w == lane_w then
		road = kept_road.el
	else
		if road_still_there() then remove_all({kept_road.el}) end
		kept_road = nil
		road = pytha.create_cylinder(mm(lanes * lane_w), mm(R), {mm(ROAD.cx), mm(ROAD.cy), mm(R)})
		pytha.rotate_element(road, {mm(ROAD.cx), mm(ROAD.cy), mm(R)}, "y", 90)		-- turn about its own base centre so it stays at x=cx
		pytha.move_element(road, {-mm(lanes * lane_w / 2), 0, 0})
		if ROAD.keep_road then kept_road = {el = road, lane_w = lane_w} else table.insert(made, road) end
	end
	if road_mat ~= nil then
		-- cylinder projection; the tile is twice as long as the road is wide and a whole number of them fit around
		local width = lanes * lane_w
		local circumference = 2 * math.pi * R
		local tiles = math.max(1, math.floor(circumference / (2 * width) + 0.5))
		local length = circumference / tiles
		local repeat_size = ROAD.road_turned and {length, width} or {width, length}
		apply_material(road, road_mat)
		try(function() pytha.set_element_attributes(road_mat, {texture_mapping = "cylinder", texture_repeat = repeat_size}) end)
	end
	-- lane marks: thin strips along the top
	local rolling = {road}
	for lane = 1, lanes - 1 do
		local mark = pytha.create_block(mm(8), mm(R * 0.4), mm(4), {mm(x0 + lane * lane_w - 4), mm(ROAD.cy - R * 0.2), mm(2 * R)})
		table.insert(rolling, mark); table.insert(made, mark)
	end
	-- obstacles sit on top (angle 0) and are rotated out to their start angle about the road axis
	local obstacles = {}
	local obstacle_els = {}		-- models turn on their own: a model's group is not reliably carried by the road group
	-- Move an obstacle to a new lane/angle. `delta_lane` is the sideways move
	-- needed to reach the new lane (0 if it's already there); the rotation is
	-- the DIFFERENCE between the new target angle and whatever angle it was
	-- last placed at (obstacle.base), so repeated calls accumulate correctly.
	local function place(obstacle, lane, angle)
		local delta_lane = (lane - (obstacle.lane or lane)) * lane_w
		if obstacle.lane == nil then delta_lane = 0 end
		if delta_lane ~= 0 then pytha.move_element(obstacle.el, {mm(delta_lane), 0, 0}) end
		pytha.rotate_element(obstacle.el, axis_point, "x", ROAD.DIR * (angle - (obstacle.base or 0)))
		obstacle.lane, obstacle.base = lane, angle
	end
	-- scatter ROAD.count obstacles evenly around the cylinder (360/count degrees apart, offset by 60 so the first
	-- one doesn't start right on top of the car), each in a random lane, using the model if one was picked,
	-- else a sphere, else (if ROAD.obstacle isn't "sphere") a textured block
	for index = 1, ROAD.count do
		local lane = math.random(1, lanes)
		local el = place_model(models.cube, mm(x0 + (lane - 0.5) * lane_w), mm(ROAD.cy), mm(2 * R), ROAD.cube_turn, spawned)
		if el == nil and ROAD.obstacle == "sphere" then
			local radius = lane_w * 0.3
			el = pytha.create_sphere(mm(radius), {mm(x0 + (lane - 0.5) * lane_w), mm(ROAD.cy), mm(2 * R + radius)})
			if ball_mat ~= nil then
				apply_material(el, ball_mat)
				try(function() pytha.set_element_attributes(ball_mat, {texture_mapping = "sphere", texture_repeat = {2 * math.pi * radius, math.pi * radius}}) end)
			end
		elseif el == nil then
			el = pytha.create_block(mm(lane_w * 0.6), mm(lane_w * 0.6), mm(lane_w * 0.6), {mm(x0 + (lane - 0.5) * lane_w - lane_w * 0.3), mm(ROAD.cy - lane_w * 0.3), mm(2 * R)})
			apply_material(el, ball_mat)
		end
		local obstacle = {el = el, lane = lane, base = 0}
		pytha.rotate_element(el, axis_point, "x", ROAD.DIR * (60 + index * 360 / ROAD.count))
		obstacle.base = 60 + index * 360 / ROAD.count
		table.insert(obstacles, obstacle); table.insert(made, el)
		if type(el) == "table" then for _, part in ipairs(el) do table.insert(obstacle_els, part) end else table.insert(obstacle_els, el) end
	end
	-- the car: the imported model if one was picked and stood in its starting lane, otherwise a plain red-pen block
	local car = car_el
	if car ~= nil then stand_model(car, mm(x0 + (state.lane - 0.5) * lane_w), mm(ROAD.cy), mm(2 * R + 4)) end
	if car == nil then
		car = pytha.create_block(mm(lane_w * 0.5), mm(lane_w * 0.9), mm(lane_w * 0.3), {mm(x0 + (state.lane - 0.5) * lane_w - lane_w * 0.25), mm(ROAD.cy - lane_w * 0.45), mm(2 * R + 4)})
		pytha.set_element_pen(car, 3)
	end
	table.insert(made, car)
	if ROAD.paint_car and car_mat ~= nil then
		if #car_track > 0 then apply_material(car_track, car_mat) else apply_material(car, car_mat) end
	end
	local car_lane = state.lane

	local label
	local function show_state(extra)
		set_label(label, string.format("Score %d   Crashes %d   Speed %d   Lane %d/%d%s", state.score, state.crashes, state.speed, state.lane, lanes, extra and ("   " .. extra) or ""))
	end
	-- move the car sideways by `step` lanes (clamped to the road's width) and update the on-screen label
	local function steer(step)
		local new_lane = math.max(1, math.min(lanes, state.lane + step))
		if new_lane ~= state.lane then
			try(function() pytha.move_element(car, {mm((new_lane - state.lane) * lane_w), 0, 0}) end)
			state.lane = new_lane
			show_state()
		end
	end
	-- Called once per timer tick while the game is running. Spins the road
	-- and every obstacle by a small amount (scaled by state.speed and by
	-- clock.rate so the game runs at the same real-world speed regardless of
	-- how fast the timer actually fires - see make_clock's comment above),
	-- then checks every obstacle's current angle:
	--   - within hit_degrees of the car's position (angle ~0) and in the
	--     car's lane and not already counted -> a crash.
	--   - just past the car (between hit_degrees and 90 degrees) and not yet
	--     counted -> scores a point if it wasn't a crash.
	--   - swung round behind (90-120 degrees) and already counted -> send it
	--     back out to a fresh random lane at the same ring position, and
	--     speed the game up a little every 8 points scored.
	local function on_frame(clock)
		local degrees = ROAD.turn_scale * state.speed * 13 / clock.rate		--per tick, scaled by the measured rate
		state.rot = (state.rot + degrees) % 360
		try(function() pytha.rotate_element(rolling, axis_point, "x", ROAD.DIR * degrees) end)
		try(function() pytha.rotate_element(obstacle_els, axis_point, "x", ROAD.DIR * degrees) end)
		for _, obstacle in ipairs(obstacles) do
			obstacle.base = obstacle.base + 0		--base is the angle at the last re-place; the group's own rotation is state.rot
			local effective = (obstacle.base + state.rot) % 360
			if effective < hit_degrees or effective > 360 - hit_degrees then
				if obstacle.lane == state.lane and not obstacle.hit then
					obstacle.hit = true
					state.crashes = state.crashes + 1
					show_state("CRASH")
				end
			elseif effective > hit_degrees and effective < 90 and not obstacle.counted then
				obstacle.counted = true
				if not obstacle.hit then state.score = state.score + 1 end
			end
			if effective > 90 and effective < 120 and obstacle.counted then		-- passed behind: send it ahead again in a new lane
				local new_lane = math.random(1, lanes)
				local new_angle = obstacle.base		-- same spot on the ring, new lane: keeps the spacing even
				try(function() place(obstacle, new_lane, new_angle) end)
				obstacle.hit, obstacle.counted = false, false
				state.speed = math.min(12, 4 + math.floor(state.score / 8))
			end
		end
		if clock.ticks % 8 == 0 then show_state() end
	end
	local clock = make_clock(on_frame)

	-- The game's own dialog: every control is a BUTTON (see the header note -
	-- arrow keys never reach the plugin, so there's no keyboard steering).
	-- The dialog stays open and modal for the whole game; Start/Stop toggle
	-- the timer, Left/Right steer, and closing the dialog (OK or Cancel) ends
	-- the game below.
	local function dialog(dlg)
		dlg:set_window_title("Playground - Road Racer")
		dlg:create_label({1, 2}, "Orbit to x=" .. ROAD.cx .. " y=" .. ROAD.cy .. ". Dodge the cubes: Left / Right, Start, Stop.")
		local left = dlg:create_button(1, "< Left")
		local right = dlg:create_button(2, "Right >")
		local start = dlg:create_button(1, "Start")
		local stop = dlg:create_button(2, "Stop")
		label = dlg:create_label({1, 2}, "Score 0")
		left:set_on_click_handler(function() steer(-1) end)
		right:set_on_click_handler(function() steer(1) end)
		start:set_on_click_handler(function() clock.start() end)
		stop:set_on_click_handler(function() clock.stop() end)
		dlg:create_ok_button(1)
		dlg:create_cancel_button(2)
	end
	pyui.run_modal_subdialog(dialog)
	-- game over (dialog closed): stop the timer first, then clean up every
	-- element this run created. `made` holds everything except the road
	-- itself (kept separately in kept_road if ROAD.keep_road is true), and
	-- `spawned` holds every part of any imported .pyo models.
	clock.stop()
	remove_all(made)
	remove_all(spawned)
	pyui.alert(string.format("Road Racer: score %d, crashes %d.%s", state.score, state.crashes,
		kept_road and "\nThe road cylinder stays in the model (texture it, then play again)." or ""))
end

----------------------------------------------------------------------------------------------------------------
-- Sheet Tetris: door-shaped parts fall onto a 4 x 8 sheet (standing up, 4 in cells); score = how much of the sheet is used
----------------------------------------------------------------------------------------------------------------
-- A straight Tetris-style game, but played against a cabinet-shop problem:
-- the "pieces" are door/panel-sized rectangles, the "board" is a sheet goods
-- layout grid, and the score is sheet utilization (how little material is
-- wasted) rather than lines cleared. SHEET.cell is one grid cell in document
-- units (4 inches); PIECES lists the {width,height} of each falling piece in
-- cells.
local SHEET = {cols = 12, rows = 24, cell = 4 * 25.4, x = 6000, z = 0, y = 5000}
local PIECES = {{2, 3}, {3, 5}, {4, 2}, {2, 6}, {3, 3}, {5, 2}, {1, 6}, {4, 4}, {6, 2}}

local function sheet_tetris()
	local cols, rows, cell = SHEET.cols, SHEET.rows, SHEET.cell
	local made = {}
	local board = {}				-- board[r][c] = true when taken (row 1 = bottom)
	for r = 1, rows do board[r] = {} end
	-- draw one piece (or the locked remains of one) as a flat block standing on the sheet's grid, at (col,row) in
	-- cells, w x h cells in size, painted with `pen`
	local function block_at(col, row, w, h, pen)
		local el = pytha.create_block(mm(w * cell), mm(20), mm(h * cell), {mm(SHEET.x + (col - 1) * cell), mm(SHEET.y), mm(SHEET.z + (row - 1) * cell)})
		pytha.set_element_pen(el, pen)
		table.insert(made, el)
		return el
	end
	local back = pytha.create_block(mm(cols * cell), mm(4), mm(rows * cell), {mm(SHEET.x), mm(SHEET.y + 22), mm(SHEET.z)})
	table.insert(made, back)
	local game = {over = false, pieces = 0, used = 0, piece = nil, drop_counter = 0, delay = 8}
	-- can a w x h piece sit with its bottom-left corner at (col,row) without
	-- going outside the board or overlapping an already-locked cell? (A piece
	-- still partly above the top row is allowed - that's just normal
	-- spawning - only a real collision with the LOCKED board below fails.)
	local function fits(col, row, w, h)
		if col < 1 or col + w - 1 > cols or row < 1 then return false end
		if row + h - 1 > rows then return true end			-- spawning above the top is fine, the board test below catches collisions
		for r = row, row + h - 1 do
			for c = col, col + w - 1 do if board[r][c] then return false end end
		end
		return true
	end
	-- create a new random piece, centred horizontally, starting with its
	-- bottom aligned to the top of the board. If it doesn't even fit there,
	-- the board is full and the game is over.
	local function spawn()
		local size = PIECES[math.random(1, #PIECES)]
		local w, h = size[1], size[2]
		local col = math.floor((cols - w) / 2) + 1
		local row = rows - h + 1
		if not fits(col, row, w, h) then game.over = true; return end
		local pen = math.random(2, 12)
		game.piece = {col = col, row = row, w = w, h = h, el = block_at(col, row, w, h, pen), pen = pen}
		game.pieces = game.pieces + 1
	end
	-- try to move the current piece by (dcol, drow) cells; returns false
	-- (and leaves it in place) if the destination doesn't fit
	local function move_piece(dcol, drow)
		local p = game.piece
		if p == nil or game.over then return false end
		if not fits(p.col + dcol, p.row + drow, p.w, p.h) then return false end
		p.col, p.row = p.col + dcol, p.row + drow
		try(function() pytha.move_element(p.el, {mm(dcol * cell), 0, mm(drow * cell)}) end)
		return true
	end
	-- the current piece has landed: mark its cells taken on the board, tally
	-- the area used, and spawn the next piece
	local function lock()
		local p = game.piece
		for r = p.row, math.min(rows, p.row + p.h - 1) do for c = p.col, p.col + p.w - 1 do board[r][c] = true end end
		game.used = game.used + p.w * p.h
		game.piece = nil
		spawn()
	end
	-- "rotate" a piece by swapping its width/height. PYTHA elements aren't
	-- rotated in place here; instead the old block is deleted and a new one
	-- drawn with the swapped dimensions at the same position (simpler than
	-- actually rotating the 3D geometry, and good enough for a game piece).
	local function rotate_piece()
		local p = game.piece
		if p == nil or game.over then return end
		local w, h = p.h, p.w
		if not fits(p.col, p.row, w, h) then return end
		try(function() pytha.delete_element(p.el) end)
		p.w, p.h = w, h
		p.el = block_at(p.col, p.row, w, h, p.pen)
	end
	local label
	local function show_state()
		local pct = 100 * game.used / (cols * rows)
		set_label(label, string.format("Parts %d   Sheet used %.0f%%   Waste so far %.0f%%%s", game.pieces, pct, 100 - pct, game.over and "   GAME OVER" or ""))
	end
	-- Called once per timer tick. Counts ticks toward the next automatic
	-- "gravity" drop (game.delay ticks per drop, scaled by the clock's real
	-- measured rate the same way road_racer() does); when the counter rolls
	-- over, try to drop the piece one row, and if it can't, lock it in place.
	-- Every 6 pieces placed, speed up slightly (lower delay) down to a floor
	-- of 3 ticks per drop.
	local function on_frame(clock)
		if game.over then return end
		game.drop_counter = game.drop_counter + 1
		if game.drop_counter >= math.max(2, math.floor(game.delay * clock.rate / 13)) then
			game.drop_counter = 0
			if not move_piece(0, -1) then lock() end
			if game.pieces % 6 == 0 and game.delay > 3 then game.delay = game.delay - 1 end
			show_state()
		end
	end
	local clock = make_clock(on_frame)
	spawn()
	-- dialog controls: move left/right, rotate, hard-drop (drop straight to
	-- the floor and lock immediately), and start/stop the gravity timer
	local function dialog(dlg)
		dlg:set_window_title("Playground - Sheet Tetris")
		dlg:create_label({1, 2}, "Orbit to x=" .. SHEET.x .. " y=" .. SHEET.y .. " and face the sheet. Fill it with as little waste as you can.")
		local left = dlg:create_button(1, "< Left")
		local right = dlg:create_button(2, "Right >")
		local turn = dlg:create_button(1, "Turn")
		local drop = dlg:create_button(2, "Drop")
		local start = dlg:create_button(1, "Start")
		local stop = dlg:create_button(2, "Stop")
		label = dlg:create_label({1, 2}, "Parts 0")
		left:set_on_click_handler(function() move_piece(-1, 0) end)
		right:set_on_click_handler(function() move_piece(1, 0) end)
		turn:set_on_click_handler(rotate_piece)
		drop:set_on_click_handler(function() while move_piece(0, -1) do end; if game.piece then lock() end; show_state() end)
		start:set_on_click_handler(function() clock.start() end)
		stop:set_on_click_handler(function() clock.stop() end)
		dlg:create_ok_button(1)
		dlg:create_cancel_button(2)
	end
	pyui.run_modal_subdialog(dialog)
	clock.stop()
	try(function() pytha.delete_element(made) end)
	local pct = 100 * game.used / (cols * rows)
	pyui.alert(string.format("Sheet Tetris: %d parts placed, %.0f%% of the sheet used (%.0f%% waste).", game.pieces, pct, 100 - pct))
end

----------------------------------------------------------------------------------------------------------------
-- picker
----------------------------------------------------------------------------------------------------------------
-- The plugin's single entry point (same pattern as Group Numbering's
-- launcher): a drop-list of the available games, then calls whichever one
-- was chosen. Any error raised by the game itself is caught here so a bug
-- mid-game shows a short error message instead of leaving PYTHA in a bad
-- state.
local GAMES = {"Road Racer", "Sheet Tetris"}

function playground()
	local choice = 1
	local function picker(dlg)
		dlg:set_window_title("Playground")
		dlg:create_label({1, 2}, "Pick a game. Everything it builds is removed when you close it.")
		dlg:create_label(1, "Game")
		local list = dlg:create_drop_list(2)
		for _, name in ipairs(GAMES) do list:insert_control_item(name) end
		list:set_control_selection(1)
		list:set_on_change_handler(function(text, new_index) choice = new_index or 1 end)
		dlg:create_ok_button(1)
		dlg:create_cancel_button(2)
	end
	if pyui.run_modal_subdialog(picker) ~= "ok" then return end
	local call_ok, err = pcall(function()
		if choice == 2 then sheet_tetris() else road_racer() end
	end)
	if not call_ok then pyui.alert("The game stopped with an error:\n" .. tostring(err):sub(1, 200)) end
end

-- toga mod
-- virtual grid for norns via TouchOSC
--
-- Devices are created dynamically when TouchOSC clients connect.
-- Each client gets assigned to the next free slot (1-4).
-- Scripts access toga grids via: local g = include('toga/lib/mod').connect(slot)

local mod = require 'core/mods'
local TogaGrid = include 'toga/lib/togagrid_class'

------------------------------------------
-- state
------------------------------------------

local toga = {
	-- connected virtual grids: slot -> TogaGrid instance
	slots = {},

	-- original osc handler
	original_osc_event = nil,

	-- mod state
	initialized = false,

	-- menu state
	menu_selected = 1
}

-- max slots (norns has 4 grid ports)
local MAX_SLOTS = 4

------------------------------------------
-- slot management
------------------------------------------

local function find_free_slot()
	for i = 1, MAX_SLOTS do
		if not toga.slots[i] then
			return i
		end
	end
	return nil
end

local function find_client_slot(ip)
	-- match by IP only (port may vary)
	for slot, device in pairs(toga.slots) do
		if device.client[1] == ip then
			return slot
		end
	end
	return nil
end

local function get_connected_slots()
	local list = {}
	for i = 1, MAX_SLOTS do
		if toga.slots[i] then
			table.insert(list, i)
		end
	end
	return list
end

------------------------------------------
-- device management
------------------------------------------

local function create_device(slot, client)
	-- generate unique id
	local id = 100 + slot

	-- create TogaGrid instance
	local device = TogaGrid.new(id, client)
	device.port = slot

	-- store in our slots table
	toga.slots[slot] = device

	print("toga: registered on slot " .. slot .. " (id=" .. id .. ", client=" .. client[1] .. ":" .. client[2] .. ")")

	-- send connection confirmation
	device:send_connected(true)

	return device
end

local function remove_device(slot)
	local device = toga.slots[slot]
	if not device then return end

	-- cleanup (clear LEDs, send disconnect)
	device:cleanup()

	print("toga: removed from slot " .. slot)

	-- clear slot
	toga.slots[slot] = nil
end

------------------------------------------
-- OSC handler
------------------------------------------

local function osc_handler(path, args, from)
	local consumed = false

	-- Debug: print all incoming OSC
	print("toga osc:", path, from[1], from[2])

	if string.sub(path, 1, 16) == "/toga_connection" then
		local ip = from[1]
		local port = from[2]

		print("toga: connection request from " .. ip .. ":" .. port)

		local existing_slot = find_client_slot(ip)
		if existing_slot then
			-- already connected, just refresh
			print("toga: client already on slot " .. existing_slot .. ", refreshing")
			local device = toga.slots[existing_slot]
			device:send_connected(true)
			device:force_refresh()
		else
			-- new client - use IP + configured response port
			local slot = find_free_slot()
			if slot then
				print("toga: assigning to slot " .. slot)
				create_device(slot, { ip, port })
			else
				print("toga: no free slots for " .. ip)
				osc.send({ ip, port }, "/toga_connection", { 0.0 })
			end
		end
		-- don't consume - togaarc might need it too
	elseif string.sub(path, 1, 10) == "/togagrid/" then
		local i = tonumber(string.sub(path, 11))
		if i then
			local x = ((i - 1) % 16) + 1
			local y = (i - 1) // 16 + 1
			local z = args[1] // 1

			local slot = find_client_slot(from[1])
			if slot then
				local device = toga.slots[slot]
				if device and device.key then
					device.key(x, y, z)
				end
			end
			consumed = true
		end
	end

	if not consumed and toga.original_osc_event then
		toga.original_osc_event(path, args, from)
	end
end

------------------------------------------
-- mod hooks
------------------------------------------

mod.hook.register("system_post_startup", "toga init", function()
	print("toga: ready for connections")

	toga.original_osc_event = osc.event
	osc.event = osc_handler
	toga.initialized = true
end)

mod.hook.register("system_pre_shutdown", "toga cleanup", function()
	print("toga: shutdown")

	if toga.initialized then
		for slot = 1, MAX_SLOTS do
			if toga.slots[slot] then
				remove_device(slot)
			end
		end

		if toga.original_osc_event then
			osc.event = toga.original_osc_event
			toga.original_osc_event = nil
		end

		toga.initialized = false
	end
end)

mod.hook.register("script_post_cleanup", "toga script cleanup", function()
	for _, device in pairs(toga.slots) do
		device:all(0)
		device:force_refresh()
	end
end)

------------------------------------------
-- mod menu
------------------------------------------

local m = {}

m.key = function(n, z)
	if n == 2 and z == 1 then
		mod.menu.exit()
	elseif n == 3 and z == 1 then
		local slots = get_connected_slots()
		if #slots > 0 and toga.menu_selected <= #slots then
			remove_device(slots[toga.menu_selected])
			toga.menu_selected = math.max(1, toga.menu_selected - 1)
		end
		mod.menu.redraw()
	end
end

m.enc = function(n, d)
	if n == 2 then
		local slots = get_connected_slots()
		if #slots > 0 then
			toga.menu_selected = util.clamp(toga.menu_selected + d, 1, #slots)
		end
	end
	mod.menu.redraw()
end

m.redraw = function()
	screen.clear()
	screen.level(15)
	screen.move(64, 10)
	screen.text_center("toga virtual grids")

	local slots = get_connected_slots()

	if #slots == 0 then
		screen.level(4)
		screen.move(64, 32)
		screen.text_center("no devices")
		screen.move(64, 44)
		screen.text_center("connect TouchOSC")
	else
		for idx, slot in ipairs(slots) do
			local device = toga.slots[slot]
			local y = 18 + idx * 10

			screen.level(idx == toga.menu_selected and 15 or 4)
			if idx == toga.menu_selected then
				screen.move(2, y)
				screen.text(">")
			end
			screen.move(10, y)
			screen.text("slot " .. slot .. ": " .. device.client[1] .. ":" .. device.client[2])
		end
	end

	screen.level(1)
	screen.move(0, 60)
	screen.text("E2:sel")
	screen.move(128, 60)
	screen.text_right("K3:disconnect")

	screen.update()
end

m.init = function()
	toga.menu_selected = 1
end

m.deinit = function() end

mod.menu.register(mod.this_name, m)

------------------------------------------
-- public API
------------------------------------------

-- Connect to a toga virtual grid by slot number
-- Usage: local g = include('toga/lib/mod').connect(1)
function toga.connect(slot)
	slot = slot or 1
	return toga.slots[slot]
end

-- Connect to first available toga grid
function toga.connect_any()
	for i = 1, MAX_SLOTS do
		if toga.slots[i] then
			return toga.slots[i]
		end
	end
	return nil
end

function toga.disconnect(slot)
	remove_device(slot)
end

function toga.get_slots()
	return toga.slots
end

function toga.get_device(slot)
	return toga.slots[slot]
end

return toga

-- toga mod
-- virtual grid for norns via TouchOSC
--
-- Devices are created dynamically when TouchOSC clients connect.
-- Each client gets assigned to the next free slot (1-4).
-- Scripts access toga grids via: local g = include('toga/lib/mod').connect(slot)

print("toga mod: loading...")

local mod = require 'core/mods'
local TogaGrid = include 'toga/lib/togagrid_class'

------------------------------------------
-- state
------------------------------------------

local toga = {
	-- connected virtual grids: slot -> TogaGrid instance
	slots = {},

	-- mod state
	initialized = false,

	-- menu state
	menu_selected = 1,

	-- callbacks (set by scripts)
	add = nil, -- function(dev) called when device connects
	remove = nil -- function(dev) called when device disconnects
}

-- max slots (norns has 4 grid ports)
local MAX_SLOTS = 4

-- vports - mirrors norns grid.vports API
-- Must be initialized early so create_device can update it
toga.vports = {}
for i = 1, MAX_SLOTS do
	toga.vports[i] = {
		name = "none",
		device = nil,
		key = nil,

		led = function(self, x, y, val)
			if self.device then self.device:led(x, y, val) end
		end,
		all = function(self, val)
			if self.device then self.device:all(val) end
		end,
		refresh = function(self)
			if self.device then self.device:refresh() end
		end,
		rotation = function(self, r)
			if self.device then self.device:rotation(r) end
		end,
		intensity = function(self, i)
			if self.device then self.device:intensity(i) end
		end,
		cols = 16,
		rows = 8
	}
end

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

	-- update vports
	if toga.vports then
		toga.vports[slot].device = device
		toga.vports[slot].name = "t" .. client[1] .. ":" .. client[2]
		device.key = function(x, y, z)
			if toga.vports[slot].key then
				toga.vports[slot].key(x, y, z)
			end
		end
	end

	print("toga: registered on slot " .. slot .. " (id=" .. id .. ", client=" .. client[1] .. ":" .. client[2] .. ")")

	-- send connection confirmation
	device:send_connected(true)

	-- call add callback if set
	if toga.add then
		toga.add(toga.vports[slot])
	end

	return device
end

local function remove_device(slot)
	local device = toga.slots[slot]
	if not device then return end

	-- call remove callback if set (before cleanup)
	if toga.remove then
		toga.remove(toga.vports[slot])
	end

	-- cleanup (clear LEDs, send disconnect)
	device:cleanup()

	print("toga: removed from slot " .. slot)

	-- clear slot
	toga.slots[slot] = nil

	-- update vports
	if toga.vports then
		toga.vports[slot].device = nil
		toga.vports[slot].name = "none"
	end
end

------------------------------------------
-- mod hooks
------------------------------------------

-- Store original _norns.osc.event handler
local original_norns_osc_event = nil

local function toga_osc_handler(path, args, from)
	-- Debug: print all incoming OSC
	-- print("toga osc:", path, from[1], from[2])

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
			-- new client
			local slot = find_free_slot()
			if slot then
				print("toga: assigning to slot " .. slot)
				create_device(slot, { ip, port })
			else
				print("toga: no free slots for " .. ip)
				osc.send({ ip, port }, "/toga_connection", { 0.0 })
			end
		end
		-- don't return - let original handler process too (for togaarc, etc)
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
			-- consumed - don't pass to original handler
			return
		end
	end

	-- call original handler for everything else
	if original_norns_osc_event then
		original_norns_osc_event(path, args, from)
	end
end

mod.hook.register("system_post_startup", "toga init", function()
	print("toga: hooking _norns.osc.event")

	-- Hook into the internal _norns.osc.event (not osc.event)
	-- This can't be overwritten by scripts
	original_norns_osc_event = _norns.osc.event
	_norns.osc.event = toga_osc_handler

	toga.initialized = true
	print("toga: ready for connections")
end)

mod.hook.register("system_pre_shutdown", "toga cleanup", function()
	print("toga: shutdown")

	if toga.initialized then
		for slot = 1, MAX_SLOTS do
			if toga.slots[slot] then
				remove_device(slot)
			end
		end

		-- restore original _norns.osc.event
		if original_norns_osc_event then
			_norns.osc.event = original_norns_osc_event
			original_norns_osc_event = nil
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

-- Update vports when slots change
local function update_vports()
	for i = 1, MAX_SLOTS do
		local device = toga.slots[i]
		if device then
			toga.vports[i].device = device
			toga.vports[i].name = "t" .. device.client[1] .. ":" .. device.client[2]
			-- Wire up key callback
			device.key = function(x, y, z)
				if toga.vports[i].key then
					toga.vports[i].key(x, y, z)
				end
			end
		else
			toga.vports[i].device = nil
			toga.vports[i].name = "none"
		end
	end
end

-- Connect like grid.connect(port)
-- Usage: local g = toga.connect(1)
function toga.connect(port)
	port = port or 1
	update_vports()
	return toga.vports[port]
end

-- Connect to first available toga grid
function toga.connect_any()
	update_vports()
	for i = 1, MAX_SLOTS do
		if toga.slots[i] then
			return toga.vports[i]
		end
	end
	return nil
end

function toga.disconnect(slot)
	remove_device(slot)
	update_vports()
end

function toga.get_slots()
	return toga.slots
end

function toga.get_device(slot)
	return toga.slots[slot]
end

return toga

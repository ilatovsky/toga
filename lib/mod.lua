-- oscgard mod
-- virtual grid for norns via TouchOSC
--
-- Devices are created dynamically when TouchOSC clients connect.
-- Each client gets assigned to the next free slot (1-4).
-- Scripts access oscgard grids via: local g = include('oscgard/lib/mod').connect(slot)

print("oscgard mod: loading...")

local mod = require 'core/mods'
local OscgardGrid = include 'oscgard/lib/oscgard_class'

------------------------------------------
-- state
------------------------------------------

local oscgard = {
	-- connected virtual grids: slot -> OscgardGrid instance
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
oscgard.vports = {}
for i = 1, MAX_SLOTS do
	oscgard.vports[i] = {
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
		if not oscgard.slots[i] then
			return i
		end
	end
	return nil
end

local function find_client_slot(ip)
	-- match by IP only (port may vary)
	for slot, device in pairs(oscgard.slots) do
		if device.client[1] == ip then
			return slot
		end
	end
	return nil
end

local function get_connected_slots()
	local list = {}
	for i = 1, MAX_SLOTS do
		if oscgard.slots[i] then
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

	-- create OscgardGrid instance
	local device = OscgardGrid.new(id, client)
	device.port = slot
	device.name = "t" .. client[1]:gsub("%D", "") .. "|" .. client[2]:gsub("%D", "")

	-- store in our slots table
	oscgard.slots[slot] = device

	-- update vports
	if oscgard.vports then
		oscgard.vports[slot].device = device
		oscgard.vports[slot].name = device.name
		device.key = function(x, y, z)
			if oscgard.vports[slot].key then
				oscgard.vports[slot].key(x, y, z)
			end
		end
	end

	print("oscgard: registered on slot " .. slot .. " (id=" .. id .. ", client=" .. client[1] .. ":" .. client[2] .. ")")

	-- send connection confirmation
	device:send_connected(true)

	-- call add callback if set
	if oscgard.add then
		oscgard.add(oscgard.vports[slot])
	end

	-- redraw mod menu if open
	mod.menu.redraw()

	return device
end

local function remove_device(slot)
	local device = oscgard.slots[slot]
	if not device then return end

	-- call remove callback if set (before cleanup)
	if oscgard.remove then
		oscgard.remove(oscgard.vports[slot])
	end

	-- cleanup (clear LEDs, send disconnect)
	device:cleanup()

	print("oscgard: removed from slot " .. slot)

	-- clear slot
	oscgard.slots[slot] = nil

	-- update vports
	if oscgard.vports then
		oscgard.vports[slot].device = nil
		oscgard.vports[slot].name = "none"
	end

	-- redraw mod menu if open
	mod.menu.redraw()
end

------------------------------------------
-- mod hooks
------------------------------------------

-- Store original _norns.osc.event handler
local original_norns_osc_event = nil

local function oscgard_osc_handler(path, args, from)
	-- Debug: print all incoming OSC
	-- print("oscgard osc:", path, from[1], from[2])

	if string.sub(path, 1, 16) == "/oscgard_connection" then
		local ip = from[1]
		local port = from[2]
		local connect = args[1] and args[1] == 1

		if connect then
			print("oscgard: connection request from " .. ip .. ":" .. port)

			local existing_slot = find_client_slot(ip)
			if existing_slot then
				-- already connected, just refresh
				print("oscgard: client already on slot " .. existing_slot .. ", refreshing")
				local device = oscgard.slots[existing_slot]
				device:send_connected(true)
				device:force_refresh()
			else
				-- new client
				local slot = find_free_slot()
				if slot then
					print("oscgard: assigning to slot " .. slot)
					create_device(slot, { ip, port })
				else
					print("oscgard: no free slots for " .. ip)
					osc.send({ ip, port }, "/oscgard_connection", { 0.0 })
				end
			end
		end
		-- don't return - let original handler process too (for oscarc, etc)
	elseif string.sub(path, 1, 10) == "/oscgard/" then
		local i = tonumber(string.sub(path, 11))
		if i then
			-- Physical coordinates from TouchOSC (always 16x8 grid)
			local px = ((i - 1) % 16) + 1
			local py = (i - 1) // 16 + 1
			local z = args[1] // 1

			local slot = find_client_slot(from[1])
			if slot then
				local device = oscgard.slots[slot]
				if device and device.key then
					-- Transform physical coords to logical coords based on rotation
					local x, y = device:transform_key(px, py)
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

mod.hook.register("system_post_startup", "oscgard init", function()
	print("oscgard: hooking _norns.osc.event")

	-- Hook into the internal _norns.osc.event (not osc.event)
	-- This can't be overwritten by scripts
	original_norns_osc_event = _norns.osc.event
	_norns.osc.event = oscgard_osc_handler

	oscgard.initialized = true
	print("oscgard: ready for connections")
end)

mod.hook.register("system_pre_shutdown", "oscgard cleanup", function()
	print("oscgard: shutdown")

	if oscgard.initialized then
		for slot = 1, MAX_SLOTS do
			if oscgard.slots[slot] then
				remove_device(slot)
			end
		end

		-- restore original _norns.osc.event
		if original_norns_osc_event then
			_norns.osc.event = original_norns_osc_event
			original_norns_osc_event = nil
		end

		oscgard.initialized = false
	end
end)

mod.hook.register("script_post_cleanup", "oscgard script cleanup", function()
	for _, device in pairs(oscgard.slots) do
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
		if #slots > 0 and oscgard.menu_selected <= #slots then
			remove_device(slots[oscgard.menu_selected])
			oscgard.menu_selected = math.max(1, oscgard.menu_selected - 1)
		end
		mod.menu.redraw()
	end
end

m.enc = function(n, d)
	if n == 2 then
		local slots = get_connected_slots()
		if #slots > 0 then
			oscgard.menu_selected = util.clamp(oscgard.menu_selected + d, 1, #slots)
		end
	end
	mod.menu.redraw()
end

m.redraw = function()
	screen.clear()
	screen.level(15)
	screen.move(64, 10)
	screen.text_center("oscgard virtual grids")

	local slots = get_connected_slots()

	if #slots == 0 then
		screen.level(4)
		screen.move(64, 32)
		screen.text_center("no devices")
		screen.move(64, 44)
		screen.text_center("connect TouchOSC")
	else
		for idx, slot in ipairs(slots) do
			local device = oscgard.slots[slot]
			local y = 18 + idx * 10

			screen.level(idx == oscgard.menu_selected and 15 or 4)
			if idx == oscgard.menu_selected then
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
	oscgard.menu_selected = 1
end

m.deinit = function() end

mod.menu.register(mod.this_name, m)

------------------------------------------
-- public API
------------------------------------------

-- Update vports when slots change
local function update_vports()
	for i = 1, MAX_SLOTS do
		local device = oscgard.slots[i]
		if device then
			oscgard.vports[i].device = device
			oscgard.vports[i].name = device.name
			-- Wire up key callback
			device.key = function(x, y, z)
				if oscgard.vports[i].key then
					oscgard.vports[i].key(x, y, z)
				end
			end
		else
			oscgard.vports[i].device = nil
			oscgard.vports[i].name = "none"
		end
	end
end

-- Connect like grid.connect(port)
-- Usage: local g = oscgard.connect(1)
function oscgard.connect(port)
	port = port or 1
	update_vports()
	return oscgard.vports[port]
end

-- Connect to first available oscgard grid
function oscgard.connect_any()
	update_vports()
	for i = 1, MAX_SLOTS do
		if oscgard.slots[i] then
			return oscgard.vports[i]
		end
	end
	return nil
end

function oscgard.disconnect(slot)
	remove_device(slot)
	update_vports()
end

function oscgard.get_slots()
	return oscgard.slots
end

function oscgard.get_device(slot)
	return oscgard.slots[slot]
end

return oscgard

-- oscgard mod
-- OSC-to-grid adapter for norns
--
-- Oscgard intercepts grid/arc API calls and routes them to any OSC client
-- app implementing the oscgard + monome device specifications.
-- Currently provides TouchOSC implementation with grid support.
--
-- Devices are created dynamically when OSC clients connect.
-- Each client gets assigned to the next free slot (1-4).
--
-- Script integration:
--   local grid = include("oscgard/lib/grid")
-- Or with hardware fallback:
--   local grid = util.file_exists(_path.code.."oscgard") and include("oscgard/lib/grid") or grid

-- Prevent multiple loading
if _G.oscgard_mod_loaded then
	return _G.oscgard_mod_instance
end

print("oscgard mod: loading...")

local mod = require 'core/mods'

local OscgardGrid = include 'oscgard/lib/oscgard_grid'
local OscgardArc = include 'oscgard/lib/oscgard_arc'

------------------------------------------
-- state
------------------------------------------

local oscgard = {
	-- mod state
	initialized = false,

	-- menu state
	menu_selected = 1,
	menu_device_type = "grid", -- "grid" or "arc"
	menu_metro = nil, -- metro for real-time menu updates

	-- serialosc-compatible settings
	prefix = "/oscgard", -- configurable OSC prefix (serialosc standard)

	notify_clients = {}, -- clients subscribed to device notifications

	-- callbacks (set by scripts) - separate for grid and arc
	grid = {
		add = nil, -- function(dev) called when grid connects
		remove = nil -- function(dev) called when grid disconnects
	},
	arc = {
		add = nil, -- function(dev) called when arc connects
		remove = nil -- function(dev) called when arc disconnects
	}
}

-- max slots (norns has 4 ports each for grid and arc)
local MAX_SLOTS = 4

-- Helper to create vport with grid-like interface
local function create_grid_vport()
	return {
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

-- Helper to create vport with arc-like interface (matches norns arc API)
local function create_arc_vport()
	return {
		name = "none",
		device = nil,
		delta = nil, -- arc encoder callback function(n, delta)
		key = nil,   -- arc key callback function(n, z)

		-- Norns arc API methods
		led = function(self, ring, x, val)
			if self.device then self.device:led(ring, x, val) end
		end,
		all = function(self, val)
			if self.device then self.device:all(val) end
		end,
		segment = function(self, ring, from_angle, to_angle, level)
			if self.device then self.device:segment(ring, from_angle, to_angle, level) end
		end,
		refresh = function(self)
			if self.device then self.device:refresh() end
		end,
		intensity = function(self, i)
			if self.device then self.device:intensity(i) end
		end,

		-- Serialosc arc protocol methods (for compatibility)
		ring_map = function(self, ring, levels)
			if self.device then self.device:ring_map(ring, levels) end
		end,
		ring_range = function(self, ring, x1, x2, val)
			if self.device then self.device:ring_range(ring, x1, x2, val) end
		end,

		encoders = 4
	}
end

-- Separate vports for grids and arcs (mirrors norns grid.vports / arc.vports)
oscgard.grid.vports = {}
oscgard.arc.vports = {}

for i = 1, MAX_SLOTS do
	oscgard.grid.vports[i] = create_grid_vport()
	oscgard.arc.vports[i] = create_arc_vport()
end

------------------------------------------
-- slot management
------------------------------------------

local function find_free_slot(device_type)
	local vports = device_type == "arc" and oscgard.arc.vports or oscgard.grid.vports
	for i = 1, MAX_SLOTS do
		if not vports[i].device then
			return i
		end
	end
	return nil
end

local function find_client_slot(ip, port, device_type)
	-- match by both IP and port
	local vports = device_type == "arc" and oscgard.arc.vports or oscgard.grid.vports
	for i = 1, MAX_SLOTS do
		local device = vports[i].device
		if device and device.client[1] == ip and device.client[2] == port then
			return i
		end
	end
	return nil
end

-- Search for a client across all device types
-- Returns: device_type, slot (or nil, nil if not found)
local function find_any_client(ip, port)
	for _, device_type in ipairs({ "grid", "arc" }) do
		local slot = find_client_slot(ip, port, device_type)
		if slot then
			return device_type, slot
		end
	end
	return nil, nil
end

------------------------------------------
-- serialosc discovery notifications
------------------------------------------

-- Forward declarations for notification functions
local notify_device_added
local notify_device_removed

-- Notify subscribed clients about device added
notify_device_added = function(device)
	for i = #oscgard.notify_clients, 1, -1 do
		local client = oscgard.notify_clients[i]
		-- /serialosc/add s <id>
		osc.send(client, "/serialosc/add", { device.serial })
		-- Remove after notifying (serialosc behavior - must re-subscribe)
		table.remove(oscgard.notify_clients, i)
	end
end

-- Notify subscribed clients about device removed
notify_device_removed = function(device)
	for i = #oscgard.notify_clients, 1, -1 do
		local client = oscgard.notify_clients[i]
		-- /serialosc/remove s <id>
		osc.send(client, "/serialosc/remove", { device.serial })
		-- Remove after notifying (serialosc behavior - must re-subscribe)
		table.remove(oscgard.notify_clients, i)
	end
end

------------------------------------------
-- device management
------------------------------------------

local function create_device(slot, client, device_type, cols, rows, serial)
	-- generate unique id (offset by device type to avoid conflicts)
	local id = (device_type == "arc" and 200 or 100) + slot

	-- default dimensions based on device type
	device_type = device_type or "grid"
	if device_type == "grid" then
		cols = cols or 16
		rows = rows or 8
	elseif device_type == "arc" then
		cols = cols or 4 -- number of encoders
		rows = rows or 64 -- LEDs per encoder
	else
		cols = cols or 16
		rows = rows or 8
	end

	-- select appropriate vports array
	local vports = device_type == "arc" and oscgard.arc.vports or oscgard.grid.vports
	local callbacks = device_type == "arc" and oscgard.arc or oscgard.grid

	local device
	if device_type == "arc" then
		device = OscgardArc.new(id, client, cols, serial)
		device.port = slot
		-- Set up delta callback
		device.delta = function(n, d)
			if vports[slot].delta then
				vports[slot].delta(n, d)
			end
		end
	else
		device = OscgardGrid.new(id, client, cols, rows, serial)
		device.port = slot
	end

	-- store in vport
	local vport = vports[slot]
	vport.device = device
	vport.name = device.name

	-- set up key callback for grid
	if device_type == "grid" then
		device.key = function(x, y, z)
			if vport.key then
				vport.key(x, y, z)
			end
		end
	end

	print("oscgard: " ..
		device_type ..
		" registered on slot " .. slot .. " (id=" .. id .. ", client=" .. client[1] .. ":" .. client[2] .. ")")

	-- send connection confirmation
	if device.send_connected then
		device:send_connected(true)
	end

	-- notify serialosc subscribers
	notify_device_added(device)

	-- call add callback if set
	if callbacks.add then
		callbacks.add(vport)
	end

	return device
end

local function remove_device(slot, device_type)
	device_type = device_type or "grid"
	local vports = device_type == "arc" and oscgard.arc.vports or oscgard.grid.vports
	local callbacks = device_type == "arc" and oscgard.arc or oscgard.grid

	local vport = vports[slot]
	local device = vport.device
	if not device then return end

	-- call remove callback if set (before cleanup)
	if callbacks.remove then
		callbacks.remove(vport)
	end

	-- cleanup (clear LEDs, send disconnect)
	device:cleanup()

	print("oscgard: " .. device_type .. " removed from slot " .. slot)

	-- clear vport
	vport.device = nil
	vport.name = "none"

	-- notify serialosc subscribers
	notify_device_removed(device)
end

------------------------------------------
-- serialosc discovery server (port 12002)
------------------------------------------

-- Handle serialosc discovery messages (normally on port 12002)
-- Note: Type tags (si, ssi, etc.) are included in comments for reference
-- with lower-level tools like oscsend/oscdump. High-level environments
-- like Max/MSP, SuperCollider, and norns infer types automatically.
local function handle_serialosc_discovery(path, args, from)
	-- /serialosc/list si <host> <port> - List all connected devices
	if path == "/serialosc/list" then
		local host = args[1] or from[1]
		local port = args[2] or from[2]
		local target = { host, port }

		-- List all grid devices
		for i = 1, MAX_SLOTS do
			local device = oscgard.grid.vports[i].device
			if device then
				-- /serialosc/device ssi <id> <type> <port>
				osc.send(target, "/serialosc/device", {
					device.serial,
					device.type,
					device.port
				})
			end
		end
		-- List all arc devices
		for i = 1, MAX_SLOTS do
			local device = oscgard.arc.vports[i].device
			if device then
				osc.send(target, "/serialosc/device", {
					device.serial,
					device.type,
					device.port
				})
			end
		end
		return true
	end

	-- /serialosc/notify si <host> <port> - Subscribe to device changes
	if path == "/serialosc/notify" then
		local host = args[1] or from[1]
		local port = args[2] or from[2]
		table.insert(oscgard.notify_clients, { host, port })
		print("oscgard: notify subscription from " .. host .. ":" .. port)
		return true
	end

	return false
end

------------------------------------------
-- serialosc system info
------------------------------------------

local function send_sys_info(client, device)
	-- /sys/id s <id>
	osc.send(client, "/sys/id", { device.serial })
	-- /sys/size ii <cols> <rows>
	osc.send(client, "/sys/size", { device.cols, device.rows })
	-- /sys/host s <host>
	osc.send(client, "/sys/host", { client[1] })
	-- /sys/port i <port>
	osc.send(client, "/sys/port", { client[2] })
	-- /sys/prefix s <prefix>
	osc.send(client, "/sys/prefix", { device.prefix or oscgard.prefix })
	-- /sys/rotation i <degrees>
	local rotation_state = device.rotation_state or 0
	osc.send(client, "/sys/rotation", { rotation_state * 90 })
end

------------------------------------------
-- mod hooks
------------------------------------------

-- Store original _norns.osc.event handler
local original_norns_osc_event = nil

-- Helper to find client in either grid or arc vports
local function find_client_any(ip, port)
	-- Check grids first
	local slot = find_client_slot(ip, port, "grid")
	if slot then
		return slot, "grid", oscgard.grid.vports[slot].device
	end
	-- Check arcs
	slot = find_client_slot(ip, port, "arc")
	if slot then
		return slot, "arc", oscgard.arc.vports[slot].device
	end
	return nil, nil, nil
end

local function oscgard_osc_handler(path, args, from)
	-- Debug: print all incoming OSC
	-- print("oscgard osc:", path, from[1], from[2])

	-- ========================================
	-- SERIALOSC DISCOVERY: /serialosc/* messages
	-- ========================================
	if handle_serialosc_discovery(path, args, from) then
		return
	end

	local ip = from[1]
	local port = from[2]
	local slot, device_type, device = find_client_any(ip, port)
	local prefix = (device and device.prefix) or oscgard.prefix

	-- ========================================
	-- SERIALOSC STANDARD: System messages
	-- ========================================

	-- /sys/info - Request device info
	if path == "/sys/info" then
		if device then
			local target = { ip, port }
			if args[1] and args[2] then
				target = { args[1], args[2] }
			elseif args[1] then
				target = { "localhost", args[1] }
			end
			send_sys_info(target, device)
		end
		return

		-- /sys/prefix - Change OSC prefix
	elseif path == "/sys/prefix" and args[1] then
		if device then
			device.prefix = args[1]
			print("oscgard: prefix changed to " .. args[1])
		else
			oscgard.prefix = args[1]
			print("oscgard: global prefix changed to " .. args[1])
		end
		return

		-- /sys/rotation - Change rotation (degrees: 0, 90, 180, 270)
	elseif path == "/sys/rotation" and args[1] then
		if device then
			local degrees = args[1]
			local rotation = degrees // 90
			if rotation >= 0 and rotation <= 3 then
				device:rotation(rotation)
				print("oscgard: rotation set to " .. degrees .. " degrees")
			end
		end
		return

		-- /sys/port - Change destination port (not typically used for oscgard)
	elseif path == "/sys/port" and args[1] then
		if device then
			device.client[2] = args[1]
			print("oscgard: destination port changed to " .. args[1])
		end
		return

		-- /sys/host - Change destination host (not typically used for oscgard)
	elseif path == "/sys/host" and args[1] then
		if device then
			device.client[1] = args[1]
			print("oscgard: destination host changed to " .. args[1])
		end
		return
	end

	-- ========================================
	-- SERIALOSC STANDARD: Grid key input
	-- ========================================

	-- <prefix>/grid/key x y s (0-indexed coordinates, standard monome format)
	if path == prefix .. "/grid/key" then
		if device and device.key and args[1] and args[2] and args[3] then
			local x = math.floor(args[1] + 1) -- Convert 0-indexed to 1-indexed
			local y = math.floor(args[2] + 1)
			local z = math.floor(args[3])
			-- Transform physical coords to logical coords based on rotation
			local lx, ly = device:transform_key(x, y)
			device.key(lx, ly, z)
		end
		return
	end

	-- ========================================
	-- SERIALOSC STANDARD: Arc encoder input
	-- ========================================

	-- <prefix>/enc/delta ii n d (0-indexed encoder, signed delta)
	if path == prefix .. "/enc/delta" then
		if device and device.delta and args[1] and args[2] then
			local n = math.floor(args[1]) + 1  -- Convert 0-indexed to 1-indexed
			local d = math.floor(args[2])      -- Signed delta value
			device.delta(n, d)
		end
		return
	end

	-- <prefix>/enc/key ii n s (0-indexed encoder, state 0/1)
	if path == prefix .. "/enc/key" then
		if device and device.key and args[1] and args[2] then
			local n = math.floor(args[1]) + 1  -- Convert 0-indexed to 1-indexed
			local z = math.floor(args[2])      -- Key state (0=up, 1=down)
			device.key(n, z)
		end
		return
	end

	-- ========================================
	-- CONNECTION: /sys/connect
	-- ========================================

	-- /sys/connect ssii <serial> <type> <cols> <rows> - Connect with full specification
	-- /sys/connect ss <serial> <type> - Connect with default dimensions
	-- /sys/connect s <serial> - Connect as default grid (16x8)
	-- /sys/connect - Connect with auto-generated serial (legacy)
	-- Types: "grid" (default), "arc"
	-- Grid sizes: 64 (8x8), 128 (16x8), 256 (16x16)
	-- Arc: cols = encoders (2 or 4), rows = 64 (LEDs per encoder)
	if path == "/sys/connect" then
		local serial = args[1]
		local device_type = args[2] or "grid"
		local cols = args[3]
		local rows = args[4]

		print("oscgard: connection request from " .. ip .. ":" .. port .. " (" .. device_type .. ")")

		-- Check if this client is already connected (on any device type)
		local existing_type, existing_slot = find_any_client(ip, port)
		if existing_slot then
			-- already connected, just refresh
			print("oscgard: client already on " .. existing_type .. " slot " .. existing_slot .. ", refreshing")
			local existing_device = oscgard[existing_type].vports[existing_slot].device
			existing_device:send_connected(true)
			existing_device:force_refresh()
			send_sys_info({ ip, port }, existing_device)
		else
			-- new client - find free slot for the requested device type
			local new_slot = find_free_slot(device_type)
			if new_slot then
				print("oscgard: assigning to " .. device_type .. " slot " .. new_slot)
				local new_device = create_device(new_slot, { ip, port }, device_type, cols, rows, serial)
				send_sys_info({ ip, port }, new_device)
			else
				print("oscgard: no free " .. device_type .. " slots for " .. ip)
				-- /sys/connect i 0 - Connection refused
				osc.send({ ip, port }, "/sys/connect", { 0 })
			end
		end
		return
	end

	-- /sys/disconnect s <serial> - Disconnect specific device by serial
	-- /sys/disconnect - Disconnect all devices from this client
	if path == "/sys/disconnect" then
		local serial = args[1]

		if serial then
			-- Disconnect specific device by serial
			local found = false
			for _, device_type in ipairs({ "grid", "arc" }) do
				local vports = device_type == "arc" and oscgard.arc.vports or oscgard.grid.vports
				for slot = 1, MAX_SLOTS do
					local device = vports[slot].device
					if device and device.serial == serial then
						print("oscgard: disconnect request for serial " .. serial .. " from " .. ip .. ":" .. port)
						remove_device(slot, device_type)
						found = true
						break
					end
				end
				if found then break end
			end
			if not found then
				print("oscgard: disconnect request for unknown serial " .. serial)
			end
		else
			-- Disconnect all devices from this client (ip:port)
			local count = 0
			for _, device_type in ipairs({ "grid", "arc" }) do
				local vports = device_type == "arc" and oscgard.arc.vports or oscgard.grid.vports
				for slot = 1, MAX_SLOTS do
					local device = vports[slot].device
					if device and device.client[1] == ip and device.client[2] == port then
						print("oscgard: disconnect " .. device_type .. " slot " .. slot .. " from " .. ip .. ":" .. port)
						remove_device(slot, device_type)
						count = count + 1
					end
				end
			end
			if count == 0 then
				print("oscgard: disconnect request from " .. ip .. ":" .. port .. " but no devices found")
			else
				print("oscgard: disconnected " .. count .. " device(s) from " .. ip .. ":" .. port)
			end
		end
		return
	end

	-- call original handler for everything else
	if original_norns_osc_event then
		original_norns_osc_event(path, args, from)
	end
end

-- Initialize OSC handler immediately (for script include mode)
-- This allows oscgard to work even when not loaded as a mod
local function init_osc_handler()
	if not oscgard.initialized and _norns and _norns.osc then
		print("oscgard: hooking _norns.osc.event")
		original_norns_osc_event = _norns.osc.event
		_norns.osc.event = oscgard_osc_handler
		oscgard.initialized = true
		print("oscgard: ready for connections")
	end
end

-- Try to initialize immediately (works when included from script after system startup)
init_osc_handler()

-- Also register hooks for proper mod loading (only if mod system is available)
if mod and mod.hook and mod.hook.register then
	-- Check if hooks are already registered by looking for our init flag
	if not _G.oscgard_hooks_registered then
		_G.oscgard_hooks_registered = true

		mod.hook.register("system_post_startup", "oscgard init", function()
			init_osc_handler()
		end)

		mod.hook.register("system_pre_shutdown", "oscgard cleanup", function()
			print("oscgard: shutdown")

			if oscgard.initialized then
				-- Cleanup both grid and arc devices
				for _, device_type in ipairs({ "grid", "arc" }) do
					for slot = 1, MAX_SLOTS do
						if oscgard[device_type].vports[slot].device then
							remove_device(slot, device_type)
						end
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
			print("calling: oscgard script cleanup")
			-- Clear both grid and arc devices when script changes
			for _, device_type in ipairs({ "grid", "arc" }) do
				for i = 1, MAX_SLOTS do
					local device = oscgard[device_type].vports[i].device
					if device then
						device:all(0)
						device:force_refresh()
					end
				end
			end
		end)
	end
end

------------------------------------------
-- mod menu
------------------------------------------

-- Helper to get all connected devices for menu display
-- Returns: array of { device_type, slot, device }
local function get_all_connected_devices()
	local devices = {}
	for _, device_type in ipairs({ "grid", "arc" }) do
		for slot = 1, MAX_SLOTS do
			local device = oscgard[device_type].vports[slot].device
			if device then
				table.insert(devices, { device_type = device_type, slot = slot, device = device })
			end
		end
	end
	return devices
end

local m = {}

m.key = function(n, z)
	if n == 2 and z == 1 then
		mod.menu.exit()
	elseif n == 3 and z == 1 then
		local devices = get_all_connected_devices()
		if #devices > 0 and oscgard.menu_selected <= #devices then
			local entry = devices[oscgard.menu_selected]
			remove_device(entry.slot, entry.device_type)
			oscgard.menu_selected = math.max(1, oscgard.menu_selected - 1)
		end
		mod.menu.redraw()
	end
end

m.enc = function(n, d)
	if n == 2 then
		local devices = get_all_connected_devices()
		if #devices > 0 then
			oscgard.menu_selected = util.clamp(oscgard.menu_selected + d, 1, #devices)
		end
	end
	mod.menu.redraw()
end

m.redraw = function()
	screen.clear()
	screen.level(15)
	screen.move(64, 10)
	screen.text_center("oscgard virtual devices")

	local devices = get_all_connected_devices()

	-- Clamp selection to valid range
	if #devices > 0 then
		oscgard.menu_selected = util.clamp(oscgard.menu_selected, 1, #devices)
	else
		oscgard.menu_selected = 1
	end

	if #devices == 0 then
		screen.level(4)
		screen.move(64, 32)
		screen.text_center("no devices")
		screen.move(64, 44)
		screen.text_center("connect TouchOSC")
	else
		for idx, entry in ipairs(devices) do
			local y = 18 + idx * 10

			screen.level(idx == oscgard.menu_selected and 15 or 4)
			if idx == oscgard.menu_selected then
				screen.move(2, y)
				screen.text(">")
			end
			screen.move(10, y)
			-- Show device type, slot, and client info
			screen.text(entry.device_type ..
				" " .. entry.slot .. ": " .. entry.device.serial)
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
	-- Start metro for real-time menu updates (2 Hz = every 0.5 seconds)
	if oscgard.menu_metro then
		oscgard.menu_metro:stop()
	end
	oscgard.menu_metro = metro.init()
	oscgard.menu_metro.time = 0.5
	oscgard.menu_metro.event = function()
		mod.menu.redraw()
	end
	oscgard.menu_metro:start()
end

m.deinit = function()
	-- Stop metro when leaving menu
	if oscgard.menu_metro then
		oscgard.menu_metro:stop()
		oscgard.menu_metro = nil
	end
end

mod.menu.register(mod.this_name, m)

------------------------------------------
-- public API
------------------------------------------

-- Grid API (matches norns grid.connect style)
-- Usage: local g = oscgard.grid.connect(1)
function oscgard.grid.connect(port)
	port = port or 1
	return oscgard.grid.vports[port]
end

-- Connect to first available oscgard grid
function oscgard.grid.connect_any()
	for i = 1, MAX_SLOTS do
		if oscgard.grid.vports[i].device then
			return oscgard.grid.vports[i]
		end
	end
	return nil
end

function oscgard.grid.disconnect(slot)
	remove_device(slot, "grid")
end

function oscgard.grid.get_slots()
	return oscgard.grid.vports
end

function oscgard.grid.get_device(slot)
	return oscgard.grid.vports[slot] and oscgard.grid.vports[slot].device
end

-- Arc API (matches norns arc.connect style)
-- Usage: local a = oscgard.arc.connect(1)
function oscgard.arc.connect(port)
	port = port or 1
	return oscgard.arc.vports[port]
end

-- Connect to first available oscgard arc
function oscgard.arc.connect_any()
	for i = 1, MAX_SLOTS do
		if oscgard.arc.vports[i].device then
			return oscgard.arc.vports[i]
		end
	end
	return nil
end

function oscgard.arc.disconnect(slot)
	remove_device(slot, "arc")
end

function oscgard.arc.get_slots()
	return oscgard.arc.vports
end

function oscgard.arc.get_device(slot)
	return oscgard.arc.vports[slot] and oscgard.arc.vports[slot].device
end

-- Mark as loaded and store instance for reuse
_G.oscgard_mod_loaded = true
_G.oscgard_mod_instance = oscgard

return oscgard

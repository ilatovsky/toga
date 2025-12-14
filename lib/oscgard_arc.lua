-- oscgard_arc.lua
-- Virtual Arc class for emulating Monome Arc devices via OSC
-- Follows norns arc API: https://monome.org/docs/norns/api/modules/arc.html

local Buffer = include 'oscgard/lib/buffer'

local OscgardArc = {}
OscgardArc.__index = OscgardArc

-- Arc device parameters
local NUM_ENCODERS = 4   -- Max encoders (Arc 2 or Arc 4)
local LEDS_PER_RING = 64 -- 64 LEDs per ring

------------------------------------------
-- Helper functions
------------------------------------------

-- Convert ring and LED position to buffer index
-- @param ring: encoder number (1-based)
-- @param x: LED position (1-based, 1-64)
-- @return buffer index (1-based)
local function ring_to_index(ring, x)
	return (ring - 1) * LEDS_PER_RING + x
end

------------------------------------------
-- State management
------------------------------------------

-- Create a new Arc device instance
-- @param id: unique device id
-- @param client: {ip, port} tuple
-- @param num_encoders: number of encoders (default 4)
-- @param serial: optional serial number (default: generated from client)
function OscgardArc.new(id, client, num_encoders, serial)
	local self = setmetatable({}, OscgardArc)

	-- Arc properties (monome API compatible)
	self.id = id or 1
	self.num_encoders = num_encoders or NUM_ENCODERS
	self.port = nil -- assigned by mod
	self.name = client[1]:gsub("%D", "") .. "|" .. client[2]:gsub("%D", "")
	self.serial = serial or ("oscgard-" .. client[1] .. ":" .. client[2])

	-- Device type for serialosc protocol
	self.device_type = "arc"

	-- Derive type name from encoder count
	if self.num_encoders == 2 then
		self.type = "monome arc 2"
	elseif self.num_encoders == 4 then
		self.type = "monome arc 4"
	else
		self.type = "monome arc"
	end

	-- Serialosc-compatible settings
	self.prefix = "/" .. self.serial -- configurable OSC prefix

	-- Client connection
	self.client = client

	-- LED state buffer (packed bitwise storage)
	local total_leds = self.num_encoders * LEDS_PER_RING
	self.buffer = Buffer.new(total_leds)

	-- Callbacks (set by scripts)
	self.delta = nil -- function(n, delta) - encoder rotation callback
	self.key = nil   -- function(n, z) - encoder key callback
	self.remove = nil -- function() - device disconnect callback

	return self
end

------------------------------------------
-- Norns Arc API Methods
------------------------------------------

-- Set single LED on ring (norns API: led(ring, x, val))
-- @param ring: encoder number (1-based)
-- @param x: LED position (1-based, 1-64)
-- @param val: brightness value (0-15)
function OscgardArc:led(ring, x, val)
	if ring < 1 or ring > self.num_encoders or x < 1 or x > LEDS_PER_RING then
		return
	end

	local index = ring_to_index(ring, x)
	self.buffer:set(index, val)

	-- Send to OSC client (arc sends immediately, no refresh needed)
	if self.client then
		-- OSC protocol uses 0-based indexing
		osc.send(self.client, self.prefix .. "/ring/set", { ring - 1, x - 1, val })
	end
end

-- Set all LEDs to uniform brightness (norns API: all(val))
-- @param val: brightness value (0-15)
function OscgardArc:all(val)
	self.buffer:set_all(val)

	-- Send to all rings
	if self.client then
		for ring = 1, self.num_encoders do
			osc.send(self.client, self.prefix .. "/ring/all", { ring - 1, val })
		end
	end
end

-- Anti-aliased arc segment from one angle to another (norns API: segment(ring, from, to, level))
-- @param ring: encoder number (1-based)
-- @param from_angle: starting angle in radians
-- @param to_angle: ending angle in radians
-- @param level: brightness value (0-15)
function OscgardArc:segment(ring, from_angle, to_angle, level)
	if ring < 1 or ring > self.num_encoders then
		return
	end

	-- Convert radians to LED positions (64 LEDs = 2π radians)
	local from_pos = (from_angle / (2 * math.pi)) * LEDS_PER_RING
	local to_pos = (to_angle / (2 * math.pi)) * LEDS_PER_RING

	-- Handle wrapping
	while from_pos < 0 do from_pos = from_pos + LEDS_PER_RING end
	while to_pos < 0 do to_pos = to_pos + LEDS_PER_RING end
	from_pos = from_pos % LEDS_PER_RING
	to_pos = to_pos % LEDS_PER_RING

	-- Clear the ring first
	for x = 1, LEDS_PER_RING do
		local index = ring_to_index(ring, x)
		self.buffer:set(index, 0)
	end

	-- Draw anti-aliased segment
	if from_pos <= to_pos then
		-- Simple case: no wrapping
		for pos = math.floor(from_pos), math.ceil(to_pos) do
			local x = (pos % LEDS_PER_RING) + 1
			local brightness = level

			-- Anti-aliasing at edges
			if pos < from_pos + 1 then
				brightness = math.floor(level * (pos - from_pos))
			elseif pos > to_pos - 1 then
				brightness = math.floor(level * (to_pos - pos + 1))
			end

			local index = ring_to_index(ring, x)
			self.buffer:set(index, math.max(0, math.min(15, brightness)))
		end
	else
		-- Wrapping case: draw in two segments
		for pos = math.floor(from_pos), LEDS_PER_RING - 1 do
			local x = (pos % LEDS_PER_RING) + 1
			local brightness = level
			if pos < from_pos + 1 then
				brightness = math.floor(level * (pos - from_pos))
			end
			local index = ring_to_index(ring, x)
			self.buffer:set(index, math.max(0, math.min(15, brightness)))
		end
		for pos = 0, math.ceil(to_pos) do
			local x = (pos % LEDS_PER_RING) + 1
			local brightness = level
			if pos > to_pos - 1 then
				brightness = math.floor(level * (to_pos - pos + 1))
			end
			local index = ring_to_index(ring, x)
			self.buffer:set(index, math.max(0, math.min(15, brightness)))
		end
	end

	-- Send ring map to client
	if self.client then
		local values = {}
		for x = 1, LEDS_PER_RING do
			local index = ring_to_index(ring, x)
			values[x] = self.buffer:get(index)
		end

		local msg = { ring - 1 }
		for i = 1, LEDS_PER_RING do
			table.insert(msg, values[i])
		end
		osc.send(self.client, self.prefix .. "/ring/map", msg)
	end
end

-- Set all LEDs on ring from array (serialosc protocol: /ring/map)
-- @param ring: encoder number (1-based)
-- @param levels: array of 64 brightness values (0-15)
function OscgardArc:ring_map(ring, levels)
	if ring < 1 or ring > self.num_encoders or #levels ~= LEDS_PER_RING then
		return
	end

	-- Update all LEDs in this ring
	for x = 1, LEDS_PER_RING do
		local index = ring_to_index(ring, x)
		self.buffer:set(index, levels[x])
	end

	-- Send to client (0-indexed for OSC)
	if self.client then
		local msg = { ring - 1 }
		for i = 1, LEDS_PER_RING do
			table.insert(msg, levels[i])
		end
		osc.send(self.client, self.prefix .. "/ring/map", msg)
	end
end

-- Set range of LEDs (serialosc protocol: /ring/range)
-- @param ring: encoder number (1-based)
-- @param x1: start LED position (1-based, 1-64)
-- @param x2: end LED position (1-based, 1-64)
-- @param val: brightness value (0-15)
function OscgardArc:ring_range(ring, x1, x2, val)
	if ring < 1 or ring > self.num_encoders then
		return
	end

	-- Normalize to 1-based and handle wrapping
	x1 = ((x1 - 1) % LEDS_PER_RING) + 1
	x2 = ((x2 - 1) % LEDS_PER_RING) + 1

	-- Update LEDs in range (clockwise with wrapping)
	local pos = x1
	local count = 0
	repeat
		local index = ring_to_index(ring, pos)
		self.buffer:set(index, val)
		count = count + 1
		if pos == x2 or count >= LEDS_PER_RING then break end
		pos = (pos % LEDS_PER_RING) + 1
	until false

	-- Send to client (0-indexed for OSC)
	if self.client then
		osc.send(self.client, self.prefix .. "/ring/range", {
			ring - 1,
			(x1 - 1) % LEDS_PER_RING,
			(x2 - 1) % LEDS_PER_RING,
			val
		})
	end
end

-- Update display (norns API: refresh())
-- Arc devices send updates immediately, so this is a no-op for compatibility
function OscgardArc:refresh()
	-- Arc updates are sent immediately in each method
	-- This method exists for API compatibility with norns
end

-- Set overall device intensity (norns API: intensity(i))
-- @param i: intensity level (0-15)
function OscgardArc:intensity(i)
	-- TouchOSC doesn't support hardware intensity
	-- This method exists for API compatibility with norns
end

------------------------------------------
-- Cleanup and lifecycle
------------------------------------------

-- Cleanup method for arc device (called on device removal)
function OscgardArc:cleanup()
	-- Call remove callback if set
	if self.remove then
		self.remove()
	end

	-- Clear LED state
	self.buffer:clear()
	self:send_disconnected()
end

------------------------------------------
-- OSC protocol methods
------------------------------------------

-- Send disconnect notification to client
function OscgardArc:send_disconnected()
	-- /sys/disconnect s <serial> - Disconnection notification
	if self.client and self.serial then
		osc.send(self.client, "/sys/disconnect", { self.serial })
	end
end

-- Send connection confirmation
function OscgardArc:send_connected()
	-- /sys/connect ssii <serial> <type> <encoders> <leds_per_ring>
	if self.client and self.serial then
		osc.send(self.client, "/sys/connect", {
			self.serial,
			self.device_type,
			self.num_encoders,
			LEDS_PER_RING
		})
	end
end

return OscgardArc

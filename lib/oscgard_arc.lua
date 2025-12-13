-- oscgard_arc.lua
-- Virtual Arc class for emulating Monome Arc devices via OSC
-- Mirrors the approach of oscgard_grid.lua


local OscgardArc = {}
OscgardArc.__index = OscgardArc
-- Send disconnect notification to client
function OscgardArc:send_disconnected()
	-- /sys/disconnect s <serial> - Disconnection notification
	if self.client and self.serial then
		osc.send(self.client, "/sys/disconnect", { self.serial })
	end
end

-- Arc device parameters
local NUM_ENCODERS = 4   -- Max encoders (Arc 2 or Arc 4)
local LEDS_PER_RING = 64 -- 64 LEDs per ring

------------------------------------------
-- State management
------------------------------------------

-- Create a new Arc device instance
function OscgardArc.new(id, num_encoders)
	local self = setmetatable({}, OscgardArc)
	self.id = id or 1
	self.num_encoders = num_encoders or NUM_ENCODERS
	self.encoders = {}
	self.rings = {}
	for i = 1, self.num_encoders do
		self.encoders[i] = 0 -- encoder position (delta)
		self.rings[i] = {}
		for j = 1, LEDS_PER_RING do
			self.rings[i][j] = 0 -- LED brightness (0-15)
		end
	end
	return self
end

------------------------------------------
-- OSC message handlers
------------------------------------------

-- Handle incoming encoder delta (/enc/delta)
function OscgardArc:handle_enc_delta(encoder, delta)
	print(string.format("[arc] handle_enc_delta: encoder=%d delta=%d", encoder, delta))
	if self.encoders[encoder] then
		self.encoders[encoder] = self.encoders[encoder] + delta
		-- TODO: trigger callback/event if needed
	end
end

-- Set single LED on ring (/ring/set n x l)
function OscgardArc:ring_set(encoder, led, value)
	print(string.format("[arc] ring_set: encoder=%d led=%d value=%d", encoder, led, value))
	encoder = encoder + 1 -- OSC is 0-based, Lua is 1-based
	led = led + 1
	if self.rings[encoder] and self.rings[encoder][led] ~= nil then
		self.rings[encoder][led] = value
		-- TODO: mark as dirty for refresh
	end
end

-- Set all LEDs on ring to value (/ring/all n l)
function OscgardArc:ring_all(encoder, value)
	print("[arc] ring_all: encoder=" .. tostring(encoder) .. " value=" .. tostring(value))
	encoder = encoder + 1
	if self.rings[encoder] then
		for i = 1, LEDS_PER_RING do
			self.rings[encoder][i] = value
		end
		-- TODO: mark as dirty for refresh
	end
end

-- Set all LEDs on ring from array (/ring/map n l[64])
function OscgardArc:ring_map(encoder, values)
	print(string.format("[arc] ring_map: encoder=%d values=[%s]", encoder, table.concat(values, ",")))
	encoder = encoder + 1
	if self.rings[encoder] and #values == LEDS_PER_RING then
		for i = 1, LEDS_PER_RING do
			self.rings[encoder][i] = values[i]
		end
		-- TODO: mark as dirty for refresh
	end
end

-- Set LEDs in a range (/ring/range n x1 x2 l)
function OscgardArc:ring_range(encoder, x1, x2, value)
	print("[arc] ring_range: encoder=" ..
	tostring(encoder) .. " x1=" .. tostring(x1) .. " x2=" .. tostring(x2) .. " value=" .. tostring(value))
	encoder = encoder + 1
	x1 = (x1 % LEDS_PER_RING) + 1
	x2 = (x2 % LEDS_PER_RING) + 1
	if not self.rings[encoder] then return end
	local i = x1
	local count = 0
	local max_iter = LEDS_PER_RING
	repeat
		self.rings[encoder][i] = value
		count = count + 1
		if i == x2 or count >= max_iter then break end
		i = (i % LEDS_PER_RING) + 1 -- wrap around
	until false
	-- TODO: mark as dirty for refresh
end

function OscgardArc:handle_enc_key(encoder, state)
	encoder = encoder + 1
	-- TODO: store key state, trigger callback/event if needed
end

-- Cleanup method for arc device (called on device removal)
function OscgardArc:cleanup()
	-- Clear LED state, reset encoders, etc. if needed
	for i = 1, self.num_encoders do
		self.encoders[i] = 0
		for j = 1, LEDS_PER_RING do
			self.rings[i][j] = 0
		end
	end
	self:send_disconnected()
end

-- Respond to /sys/info request (stub)
function OscgardArc:send_info(dest_host, dest_port)
	-- TODO: send /sys/id, /sys/size, /sys/host, /sys/port, /sys/prefix, etc.
end

-- (Add methods for device info, OSC registration, etc.)
return OscgardArc

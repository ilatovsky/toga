-- togagrid_class.lua
-- Virtual grid class for creating multiple independent grid instances
-- Used by mod.lua to create per-client grids

local TogaGrid = {}
TogaGrid.__index = TogaGrid

-- Packed state configuration (shared)
local LEDS_PER_WORD = 8 -- 8 LEDs per 32-bit number (4 bits each)
local BITS_PER_LED = 4  -- 4 bits = 16 brightness levels (0-15)

------------------------------------------
-- packed buffer operations (local functions)
------------------------------------------

local function create_packed_buffer(width, height)
	local total_leds = width * height
	local num_words = math.ceil(total_leds / LEDS_PER_WORD)
	local buffer = {}
	for i = 1, num_words do
		buffer[i] = 0
	end
	return buffer
end

local function create_dirty_flags(width, height)
	local total_leds = width * height
	local num_words = math.ceil(total_leds / 32)
	local dirty = {}
	for i = 1, num_words do
		dirty[i] = 0
	end
	return dirty
end

local function grid_to_index(x, y, cols)
	return (y - 1) * cols + (x - 1) + 1
end

local function transform_coordinates(x, y, rotation, cols, rows)
	if rotation == 0 then
		return x, y
	elseif rotation == 1 then
		return y, cols + 1 - x
	elseif rotation == 2 then
		return cols + 1 - x, rows + 1 - y
	elseif rotation == 3 then
		return rows + 1 - y, x
	end
	return x, y
end

local function get_led_from_packed(buffer, index)
	local word_index = math.floor((index - 1) / LEDS_PER_WORD) + 1
	local led_offset = (index - 1) % LEDS_PER_WORD
	local bit_shift = led_offset * BITS_PER_LED
	local mask = (1 << BITS_PER_LED) - 1
	if not buffer[word_index] then
		return 0
	end
	return (buffer[word_index] >> bit_shift) & mask
end

local function set_led_in_packed(buffer, index, brightness)
	local word_index = math.floor((index - 1) / LEDS_PER_WORD) + 1
	local led_offset = (index - 1) % LEDS_PER_WORD
	local bit_shift = led_offset * BITS_PER_LED
	local mask = (1 << BITS_PER_LED) - 1
	local clear_mask = ~(mask << bit_shift)
	buffer[word_index] = (buffer[word_index] & clear_mask) | ((brightness & mask) << bit_shift)
end

local function set_dirty_bit(dirty_array, index)
	local word_index = math.floor((index - 1) / 32) + 1
	local bit_index = (index - 1) % 32
	dirty_array[word_index] = dirty_array[word_index]| (1 << bit_index)
end

local function clear_all_dirty_bits(dirty_array)
	for i = 1, #dirty_array do
		dirty_array[i] = 0
	end
end

local function has_dirty_bits(dirty_array)
	for i = 1, #dirty_array do
		if dirty_array[i] ~= 0 then
			return true
		end
	end
	return false
end

------------------------------------------
-- TogaGrid class
------------------------------------------

function TogaGrid.new(id, client)
	local self = setmetatable({}, TogaGrid)

	-- Grid properties (monome API compatible)
	self.id = id
	self.cols = 16
	self.rows = 8
	self.port = nil -- assigned by mod
	self.name = client[1] .. ":" .. client[2]
	self.serial = "toga-" .. client[1] .. ":" .. client[2]

	-- Client connection
	self.client = client

	-- State buffers
	self.old_buffer = create_packed_buffer(self.cols, self.rows)
	self.new_buffer = create_packed_buffer(self.cols, self.rows)
	self.dirty = create_dirty_flags(self.cols, self.rows)

	-- Rotation
	self.rotation_state = 0

	-- Refresh throttling
	self.last_refresh_time = 0
	self.refresh_interval = 0.01667 -- 30Hz

	-- Callback (set by scripts)
	self.key = nil

	return self
end

function TogaGrid:led(x, y, z)
	if x < 1 or x > self.cols or y < 1 or y > self.rows then
		return
	end

	local storage_x, storage_y = transform_coordinates(x, y, self.rotation_state, self.cols, self.rows)
	if storage_x < 1 or storage_x > self.cols or storage_y < 1 or storage_y > self.rows then
		return
	end

	local index = grid_to_index(storage_x, storage_y, self.cols)
	local brightness = math.max(0, math.min(15, z))
	local current = get_led_from_packed(self.new_buffer, index)

	if current ~= brightness then
		set_led_in_packed(self.new_buffer, index, brightness)
		set_dirty_bit(self.dirty, index)
	end
end

function TogaGrid:all(z)
	local total_leds = self.cols * self.rows
	local brightness = math.max(0, math.min(15, z))
	for i = 1, total_leds do
		set_led_in_packed(self.new_buffer, i, brightness)
		set_dirty_bit(self.dirty, i)
	end
end

function TogaGrid:refresh()
	local now = util.time()
	if (now - self.last_refresh_time) < self.refresh_interval then
		return
	end
	self.last_refresh_time = now

	if has_dirty_bits(self.dirty) then
		self:send_bulk_grid_state()
		for i = 1, #self.new_buffer do
			self.old_buffer[i] = self.new_buffer[i]
		end
		clear_all_dirty_bits(self.dirty)
	end
end

function TogaGrid:force_refresh()
	for i = 1, #self.dirty do
		self.dirty[i] = 0xFFFFFFFF
	end
	self:send_bulk_grid_state()
	for i = 1, #self.new_buffer do
		self.old_buffer[i] = self.new_buffer[i]
	end
	clear_all_dirty_bits(self.dirty)
end

function TogaGrid:intensity(i)
	-- TouchOSC doesn't support hardware intensity
end

function TogaGrid:rotation(val)
	if val >= 0 and val <= 3 then
		self.rotation_state = val
		print("toga: rotation set to " .. (val * 90) .. " degrees")
		self:force_refresh()
	end
end

function TogaGrid:send_bulk_grid_state()
	local grid_data = {}
	local total_leds = self.cols * self.rows

	for i = 1, total_leds do
		local brightness = get_led_from_packed(self.new_buffer, i)
		grid_data[i] = string.format("%X", brightness)
	end

	local hex_string = table.concat(grid_data)
	osc.send(self.client, "/togagrid_bulk", { hex_string })
end

function TogaGrid:send_connected(connected)
	osc.send(self.client, "/toga_connection", { connected and 1.0 or 0.0 })
end

function TogaGrid:cleanup()
	self:all(0)
	self:force_refresh()
	self:send_connected(false)
end

return TogaGrid

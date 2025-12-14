-- buffer.lua
-- Shared packed buffer module for LED state management
-- Used by both oscgard_grid and oscgard_arc for efficient LED storage
--
-- Features:
-- - Packed bitwise storage (4 bits per LED = 16 brightness levels)
-- - Dirty bit tracking for efficient updates
-- - Memory-efficient: 8 LEDs per 32-bit word

local Buffer = {}
Buffer.__index = Buffer

-- Configuration
local MAX_BITS_PER_NUMBER_IN_LUA = 32
local BITS_PER_LED = 4 -- 4 bits = 16 brightness levels (0-15)
local LEDS_PER_WORD = MAX_BITS_PER_NUMBER_IN_LUA / BITS_PER_LED -- 8 LEDs per word

------------------------------------------
-- Buffer Creation
------------------------------------------

--- Create a new buffer instance for LED state management
-- @param total_leds: total number of LEDs to store
-- @return Buffer instance with packed storage and dirty flags
function Buffer.new(total_leds)
	local self = setmetatable({}, Buffer)

	self.total_leds = total_leds
	self.num_words = math.ceil(total_leds / LEDS_PER_WORD)
	self.num_dirty_words = math.ceil(total_leds / 32)

	-- Create packed LED buffers (old and new state)
	self.old_buffer = {}
	self.new_buffer = {}
	for i = 1, self.num_words do
		self.old_buffer[i] = 0
		self.new_buffer[i] = 0
	end

	-- Create dirty flags (1 bit per LED)
	self.dirty = {}
	for i = 1, self.num_dirty_words do
		self.dirty[i] = 0
	end

	return self
end

------------------------------------------
-- LED Operations
------------------------------------------

--- Get LED brightness at index
-- @param index: LED index (1-based)
-- @return brightness value (0-15), or 0 if out of bounds
function Buffer:get(index)
	if index < 1 or index > self.total_leds then
		return 0
	end

	local word_index = math.floor((index - 1) / LEDS_PER_WORD) + 1
	local led_offset = (index - 1) % LEDS_PER_WORD
	local bit_shift = led_offset * BITS_PER_LED
	local mask = (1 << BITS_PER_LED) - 1 -- 0x0F

	if not self.new_buffer[word_index] then
		return 0
	end

	return (self.new_buffer[word_index] >> bit_shift) & mask
end

--- Set LED brightness at index
-- @param index: LED index (1-based)
-- @param brightness: brightness value (0-15)
function Buffer:set(index, brightness)
	if index < 1 or index > self.total_leds then
		return
	end

	brightness = math.max(0, math.min(15, brightness))

	-- Check if value actually changed
	local current = self:get(index)
	if current == brightness then
		return
	end

	-- Update packed buffer
	local word_index = math.floor((index - 1) / LEDS_PER_WORD) + 1
	local led_offset = (index - 1) % LEDS_PER_WORD
	local bit_shift = led_offset * BITS_PER_LED
	local mask = (1 << BITS_PER_LED) - 1
	local clear_mask = ~(mask << bit_shift)

	self.new_buffer[word_index] = (self.new_buffer[word_index] & clear_mask) |
	                               ((brightness & mask) << bit_shift)

	-- Mark as dirty
	self:set_dirty(index)
end

--- Set all LEDs to same brightness
-- @param brightness: brightness value (0-15)
function Buffer:set_all(brightness)
	brightness = math.max(0, math.min(15, brightness))

	for i = 1, self.total_leds do
		local word_index = math.floor((i - 1) / LEDS_PER_WORD) + 1
		local led_offset = (i - 1) % LEDS_PER_WORD
		local bit_shift = led_offset * BITS_PER_LED
		local mask = (1 << BITS_PER_LED) - 1
		local clear_mask = ~(mask << bit_shift)

		self.new_buffer[word_index] = (self.new_buffer[word_index] & clear_mask) |
		                               ((brightness & mask) << bit_shift)

		self:set_dirty(i)
	end
end

------------------------------------------
-- Dirty Flag Operations
------------------------------------------

--- Mark LED at index as dirty
-- @param index: LED index (1-based)
function Buffer:set_dirty(index)
	if index < 1 or index > self.total_leds then
		return
	end

	local word_index = math.floor((index - 1) / 32) + 1
	local bit_index = (index - 1) % 32
	self.dirty[word_index] = self.dirty[word_index] | (1 << bit_index)
end

--- Check if any LEDs are dirty
-- @return true if any changes pending
function Buffer:has_dirty()
	for i = 1, self.num_dirty_words do
		if self.dirty[i] ~= 0 then
			return true
		end
	end
	return false
end

--- Clear all dirty flags
function Buffer:clear_dirty()
	for i = 1, self.num_dirty_words do
		self.dirty[i] = 0
	end
end

--- Mark all LEDs as dirty
function Buffer:mark_all_dirty()
	for i = 1, self.num_dirty_words do
		self.dirty[i] = 0xFFFFFFFF
	end
end

------------------------------------------
-- State Management
------------------------------------------

--- Commit new state to old state (call after sending updates)
function Buffer:commit()
	for i = 1, self.num_words do
		self.old_buffer[i] = self.new_buffer[i]
	end
end

--- Reset buffer to all zeros
function Buffer:clear()
	for i = 1, self.num_words do
		self.new_buffer[i] = 0
	end
	self:mark_all_dirty()
end

------------------------------------------
-- Serialization
------------------------------------------

--- Convert buffer to hex string for OSC transmission
-- @return hex string (e.g., "F00A..." with total_leds characters)
function Buffer:to_hex_string()
	local hex_chars = {}

	for i = 1, self.total_leds do
		local brightness = self:get(i)
		hex_chars[i] = string.format("%X", brightness)
	end

	return table.concat(hex_chars)
end

--- Update buffer from hex string
-- @param hex_string: hex string with brightness values (0-F per LED)
function Buffer:from_hex_string(hex_string)
	local len = math.min(#hex_string, self.total_leds)

	for i = 1, len do
		local hex_char = hex_string:sub(i, i)
		local brightness = tonumber(hex_char, 16) or 0
		self:set(i, brightness)
	end
end

------------------------------------------
-- Statistics
------------------------------------------

--- Get buffer statistics
-- @return table with memory usage info
function Buffer:stats()
	return {
		total_leds = self.total_leds,
		buffer_bytes = self.num_words * 4, -- 4 bytes per 32-bit word
		dirty_bytes = self.num_dirty_words * 4,
		total_bytes = (self.num_words + self.num_dirty_words) * 2 * 4, -- old + new buffers + dirty
		leds_per_word = LEDS_PER_WORD,
		bits_per_led = BITS_PER_LED
	}
end

return Buffer

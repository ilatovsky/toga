-- UNCOMMENT TO add midigrid plugin
--local grid = util.file_exists(_path.code.."midigrid") and include "midigrid/lib/mg_128" or grid

local togagrid = {
  device = nil, -- needed by cheat codes 2
  cols = 16,
  rows = 8,
  old_buffer = nil,
  new_buffer = nil,
  dirty = nil, -- dirty flag array for tracking changes
  dest = {},
  cleanup_done = false,
  old_grid = nil,
  old_osc_in = nil,
  old_cleanup = nil,
  key = nil,                  -- key event callback
  last_refresh_time = 0,      -- for throttling
  refresh_interval = 0.01667, -- 30Hz refresh rate (33ms)

  -- Packed state configuration
  leds_per_word = 8, -- 8 LEDs per 32-bit number (4 bits each = 32 bits)
  bits_per_led = 4   -- 4 bits = 16 brightness levels (0-15)
}

function togagrid:connect()
  if _ENV.togagrid then return _ENV.togagrid end
  togagrid:init()
  _ENV.togagrid = togagrid
  return togagrid
end

-- Create packed state buffer using bitwise storage
-- Each 32-bit number stores 8 LEDs (4 bits each)
-- For 16x8 grid (128 LEDs): 128/8 = 16 numbers
local function create_packed_buffer(width, height, leds_per_word)
  local total_leds = width * height
  local num_words = math.ceil(total_leds / leds_per_word)
  local buffer = {}

  for i = 1, num_words do
    buffer[i] = 0 -- Each word starts as 0x00000000
  end

  return buffer
end

-- Create binary dirty flags as bit array (using numbers)
-- Each number holds 32 bits, so we need ceil(total_leds / 32) numbers
local function create_dirty_flags(width, height)
  local total_leds = width * height
  local num_words = math.ceil(total_leds / 32)
  local dirty = {}

  for i = 1, num_words do
    dirty[i] = 0 -- 32-bit integer, all flags initially false
  end

  return dirty
end

-- Convert 2D grid coordinates to LED index
local function grid_to_index(x, y, cols)
  return (y - 1) * cols + (x - 1) + 1
end

-- Get LED brightness from packed buffer using bitwise operations
local function get_led_from_packed(buffer, index, leds_per_word, bits_per_led)
  local word_index = math.floor((index - 1) / leds_per_word) + 1
  local led_offset = (index - 1) % leds_per_word
  local bit_shift = led_offset * bits_per_led
  local mask = (1 << bits_per_led) - 1 -- 0x0F for 4 bits

  return (buffer[word_index] >> bit_shift) & mask
end

-- Set LED brightness in packed buffer using bitwise operations
local function set_led_in_packed(buffer, index, brightness, leds_per_word, bits_per_led)
  local word_index = math.floor((index - 1) / leds_per_word) + 1
  local led_offset = (index - 1) % leds_per_word
  local bit_shift = led_offset * bits_per_led
  local mask = (1 << bits_per_led) - 1 -- 0x0F for 4 bits

  -- Clear the old value and set the new one
  local clear_mask = ~(mask << bit_shift)
  buffer[word_index] = (buffer[word_index] & clear_mask) | ((brightness & mask) << bit_shift)
end

-- Set dirty bit for given LED index
local function set_dirty_bit(dirty_array, index)
  local word_index = math.floor((index - 1) / 32) + 1
  local bit_index = (index - 1) % 32
  dirty_array[word_index] = dirty_array[word_index]| (1 << bit_index)
end

-- Clear all dirty bits
local function clear_all_dirty_bits(dirty_array)
  for i = 1, #dirty_array do
    dirty_array[i] = 0
  end
end

-- Check if any dirty bits are set
local function has_dirty_bits(dirty_array)
  for i = 1, #dirty_array do
    if dirty_array[i] ~= 0 then
      return true
    end
  end
  return false
end

function togagrid:init()
  -- UNCOMMENT to add default touchosc client
  --table.insert(self.dest, {"192.168.0.123",8002})

  self.device = self
  self.old_buffer = create_packed_buffer(self.cols, self.rows, self.leds_per_word)
  self.new_buffer = create_packed_buffer(self.cols, self.rows, self.leds_per_word)
  self.dirty = create_dirty_flags(self.cols, self.rows)
  self:hook_osc_in()
  self:hook_cleanup()
  self:refresh(true)

  self.old_grid = grid.connect()
  if self.old_grid then
    self.old_grid.key = function(x, y, z)
      if togagrid.key then
        togagrid.key(x, y, z)
      else
        --print("grid.key is not defined!")
      end
    end
  end

  self:send_connected(nil, true)
end

-- @static
function togagrid.osc_in(path, args, from)
  local consumed = false
  if not togagrid.cleanup_done then
    local x, y, z, i
    --print("togagrid_osc_in", dump(path), dump(args), dump(from))
    if string.sub(path, 1, 16) == "/toga_connection" then
      print("togagrid connect!")
      local added = false
      for d, dest in pairs(togagrid.dest) do
        if dest[1] == from[1] and dest[2] == from[2] then
          added = true
        end
      end
      if not added then
        print("togagrid: add new toga client", from[1] .. ":" .. from[2])
        table.insert(togagrid.dest, from)
        togagrid:refresh(true, from)
      end
      -- echo back anyway to update connection button value
      togagrid:send_connected(from, true)
      -- do not consume the event so togaarc can also add the new touchosc client.
    elseif string.sub(path, 1, 10) == "/togagrid/" then
      i = tonumber(string.sub(path, 11))
      x = ((i - 1) % 16) + 1
      y = (i - 1) // 16 + 1
      z = args[1] // 1
      --print("togagrid_osc_in togagrid", i, x, y, z)
      if togagrid.key then
        togagrid.key(x, y, z)
      end
      -- Removed immediate LED update on button release - let next refresh handle it
      consumed = true
    end
  end

  if not consumed then
    -- invoking original osc.event callback if it exists
    if togagrid.old_osc_in then
      togagrid.old_osc_in(path, args, from)
    end
  end
end

function togagrid:hook_osc_in()
  if togagrid.old_osc_in ~= nil then return end
  --print("togagrid: hook old osc_in")
  togagrid.old_osc_in = osc.event
  osc.event = togagrid.osc_in
end

-- @static
function togagrid.cleanup()
  if togagrid.old_cleanup then
    togagrid.old_cleanup()
  end
  if not togagrid.cleanup_done then
    -- Clear all LEDs before disconnecting
    print("togagrid: clearing all LEDs on script shutdown")
    togagrid:all(0)
    togagrid:refresh(true) -- Force immediate refresh to clear all LEDs

    -- Send disconnected signal
    togagrid:send_connected(nil, false)
    togagrid.cleanup_done = true
  end
end

function togagrid:hook_cleanup()
  if togagrid.old_cleanup ~= nil then return end
  --print("togagrid: hook old cleanup")
  togagrid.old_cleanup = grid.cleanup
  grid.cleanup = togagrid.cleanup
end

function togagrid:rotation(val)
  if self.old_grid then
    self.old_grid:rotation(val)
  end
end

function togagrid:all(z)
  local total_leds = self.cols * self.rows
  local brightness = math.max(0, math.min(15, z))

  -- Set all LEDs to same brightness using packed operations
  for i = 1, total_leds do
    set_led_in_packed(self.new_buffer, i, brightness, self.leds_per_word, self.bits_per_led)
    set_dirty_bit(self.dirty, i)
  end

  if self.old_grid then
    self.old_grid:all(z)
  end
end

function togagrid:led(x, y, z)
  if x < 1 or x > self.cols or y < 1 or y > self.rows then return end

  local index = grid_to_index(x, y, self.cols)
  local brightness = math.max(0, math.min(15, z))

  -- Get current value using bitwise operations
  local current = get_led_from_packed(self.new_buffer, index, self.leds_per_word, self.bits_per_led)

  if current ~= brightness then
    -- Set new value using bitwise operations
    set_led_in_packed(self.new_buffer, index, brightness, self.leds_per_word, self.bits_per_led)
    set_dirty_bit(self.dirty, index)
  end

  if self.old_grid then
    self.old_grid:led(x, y, z)
  end
end

function togagrid:refresh(force_refresh, target_dest)
  -- Throttle refresh to 30Hz unless forced
  if not force_refresh then
    local now = util.time()
    if (now - self.last_refresh_time) < self.refresh_interval then
      return -- Skip this refresh, too soon
    end
    self.last_refresh_time = now
  end

  -- Always use bulk update - send entire grid state in one message
  local has_changes = force_refresh or has_dirty_bits(self.dirty)

  if has_changes then
    self:send_bulk_grid_state(target_dest)
    -- Copy new_buffer to old_buffer (packed word by word)
    for i = 1, #self.new_buffer do
      self.old_buffer[i] = self.new_buffer[i]
    end
    clear_all_dirty_bits(self.dirty)
  end

  if self.old_grid then
    self.old_grid:refresh()
  end
end

function togagrid:intensity(i)
  if self.old_grid then
    self.old_grid:intensity(i)
  end
end

function togagrid:send_connected(target_dest, connected)
  for d, dest in pairs(self.dest) do
    if target_dest and (target_dest[1] ~= dest[1] or target_dest[2] ~= dest[2]) then
      -- do nothing
    else
      osc.send(dest, "/toga_connection", { connected and 1.0 or 0.0 })
    end
  end
end

-- Send entire grid state as bulk update
-- Format: /togagrid_bulk with array of 128 hex values (extracted from packed buffer)
-- Each value represents brightness level 0-15 encoded as hex string
function togagrid:send_bulk_grid_state(target_dest)
  local grid_data = {}
  local total_leds = self.cols * self.rows

  -- Extract hex values from packed buffer using bitwise operations
  for i = 1, total_leds do
    local brightness = get_led_from_packed(self.new_buffer, i, self.leds_per_word, self.bits_per_led)
    -- Convert to hex string (0-F)
    grid_data[i] = string.format("%X", brightness)
  end

  -- Convert array to single string for better OSC compatibility
  local hex_string = table.concat(grid_data)

  -- Send as single OSC message with hex string
  for d, dest in pairs(self.dest) do
    if target_dest and (target_dest[1] ~= dest[1] or target_dest[2] ~= dest[2]) then
      -- do nothing
    else
      osc.send(dest, "/togagrid_bulk", { hex_string })
    end
  end
end -- Alternative compact format: send as single hex string

-- Format: /togagrid_compact with single string of 128 hex characters
function togagrid:send_compact_grid_state(target_dest)
  local hex_chars = {}
  local total_leds = self.cols * self.rows

  -- Build hex character array first (faster than string concatenation)
  for i = 1, total_leds do
    local brightness = get_led_from_packed(self.new_buffer, i, self.leds_per_word, self.bits_per_led)
    -- Convert to hex char (0-F)
    hex_chars[i] = string.format("%X", brightness)
  end

  -- Join all hex characters into single string
  local hex_string = table.concat(hex_chars)

  -- Send as single OSC message with hex string
  for d, dest in pairs(self.dest) do
    if target_dest and (target_dest[1] ~= dest[1] or target_dest[2] ~= dest[2]) then
      -- do nothing
    else
      osc.send(dest, "/togagrid_compact", { hex_string })
    end
  end
end

-- Get grid info
function togagrid:get_info()
  return {
    total_leds = self.cols * self.rows,
    packed_words = math.ceil((self.cols * self.rows) / self.leds_per_word),
    leds_per_word = self.leds_per_word,
    bits_per_led = self.bits_per_led,
    memory_usage = math.ceil((self.cols * self.rows) / self.leds_per_word) * 4 -- bytes
  }
end

return togagrid

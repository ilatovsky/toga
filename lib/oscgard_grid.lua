-- oscgard_grid.lua
-- Virtual grid class for creating multiple independent grid instances
-- Used by mod.lua to create per-client grids

local Buffer = include 'oscgard/lib/buffer'

local OscgardGrid = {}
OscgardGrid.__index = OscgardGrid

------------------------------------------
-- coordinate operations
------------------------------------------

local function grid_to_index(x, y, cols)
	return (y - 1) * cols + (x - 1) + 1
end

local function transform_coordinates(x, y, rotation, cols, rows)
	-- Transform from logical coordinates to physical storage coordinates
	-- Physical storage is always 16x8 (cols x rows)
	--
	-- rotation 0: no rotation, logical 16x8 -> physical 16x8
	-- rotation 1: 90° CW, logical 8x16 -> physical 16x8
	-- rotation 2: 180°, logical 16x8 -> physical 16x8
	-- rotation 3: 270° CW, logical 8x16 -> physical 16x8

	if rotation == 0 then
		return x, y
	elseif rotation == 1 then
		-- 90° CW: swap and flip
		-- logical (1,1) -> physical (1,8)
		-- logical (8,1) -> physical (1,1)
		-- logical (1,16) -> physical (16,8)
		return y, rows + 1 - x
	elseif rotation == 2 then
		-- 180°: flip both
		return cols + 1 - x, rows + 1 - y
	elseif rotation == 3 then
		-- 270° CW: swap and flip other way
		-- logical (1,1) -> physical (16,1)
		-- logical (8,1) -> physical (16,8)
		-- logical (1,16) -> physical (1,1)
		-- logical (8,16) -> physical (1,8)
		return cols + 1 - y, x
	end
	return x, y
end

------------------------------------------
-- OscgardGrid class
------------------------------------------

-- Create new OscgardGrid instance
-- @param id: unique device id
-- @param client: {ip, port} tuple
-- @param cols: number of columns (default 16)
-- @param rows: number of rows (default 8)
-- @param serial: optional serial number (default: generated from client)
function OscgardGrid.new(id, client, cols, rows, serial)
	local self = setmetatable({}, OscgardGrid)

	-- Grid properties (monome API compatible)
	self.id = id
	self.cols = cols or 16
	self.rows = rows or 8
	self.port = nil -- assigned by mod
	self.name = client[1]:gsub("%D", "") .. "|" .. client[2]:gsub("%D", "")
	self.serial = serial or ("oscgard-" .. client[1] .. ":" .. client[2])

	-- Device type for serialosc protocol
	self.device_type = "grid"

	-- Derive type name from dimensions
	local total_leds = self.cols * self.rows
	if total_leds == 64 then
		self.type = "monome 64"
	elseif total_leds == 128 then
		self.type = "monome 128"
	elseif total_leds == 256 then
		self.type = "monome 256"
	else
		self.type = "monome " .. total_leds
	end

	-- Serialosc-compatible settings
	self.prefix = "/" .. self.serial -- configurable OSC prefix

	-- Client connection
	self.client = client

	-- LED state buffer (packed bitwise storage with dirty flags)
	local total_leds = self.cols * self.rows
	self.buffer = Buffer.new(total_leds)

	-- Rotation
	self.rotation_state = 0

	-- Refresh throttling
	self.last_refresh_time = 0
	self.refresh_interval = 0.01667 -- 30Hz

	-- Callback (set by scripts)
	self.key = nil

	return self
end

function OscgardGrid:led(x, y, z)
	-- Get logical dimensions based on rotation
	-- Rotation 0, 2: logical is 16x8 (same as physical)
	-- Rotation 1, 3: logical is 8x16 (swapped)
	local logical_cols, logical_rows
	if self.rotation_state == 1 or self.rotation_state == 3 then
		logical_cols = self.rows -- 8
		logical_rows = self.cols -- 16
	else
		logical_cols = self.cols -- 16
		logical_rows = self.rows -- 8
	end

	-- Check bounds against logical dimensions
	if x < 1 or x > logical_cols or y < 1 or y > logical_rows then
		return
	end

	local storage_x, storage_y = transform_coordinates(x, y, self.rotation_state, self.cols, self.rows)
	if storage_x < 1 or storage_x > self.cols or storage_y < 1 or storage_y > self.rows then
		return
	end

	local index = grid_to_index(storage_x, storage_y, self.cols)
	self.buffer:set(index, z)
end

function OscgardGrid:all(z)
	self.buffer:set_all(z)
end

function OscgardGrid:refresh()
	local now = util.time()
	if (now - self.last_refresh_time) < self.refresh_interval then
		return
	end
	self.last_refresh_time = now

	if self.buffer:has_dirty() then
		local hex_string = self.buffer:to_hex_string()
		self:send_level_full(hex_string)
		self.buffer:commit()
		self.buffer:clear_dirty()
	end
end

function OscgardGrid:force_refresh()
	self.buffer:mark_all_dirty()
	local hex_string = self.buffer:to_hex_string()
	self:send_level_full(hex_string)
	self.buffer:commit()
	self.buffer:clear_dirty()
end

function OscgardGrid:intensity(i)
	-- TouchOSC doesn't support hardware intensity
end

function OscgardGrid:rotation(val)
	if val >= 0 and val <= 3 then
		self.rotation_state = val
		print("oscgard: rotation set to " .. (val * 90) .. " degrees")
		self:force_refresh()
	end
end

-- Transform physical key coordinates (from TouchOSC) to logical coordinates
-- This is the inverse of transform_coordinates
function OscgardGrid:transform_key(px, py)
	local cols, rows = self.cols, self.rows -- 16, 8

	if self.rotation_state == 0 then
		return px, py
	elseif self.rotation_state == 1 then
		-- Inverse of: return y, rows + 1 - x
		-- physical (px, py) came from logical (rows + 1 - py, px)
		return rows + 1 - py, px
	elseif self.rotation_state == 2 then
		-- Inverse of: return cols + 1 - x, rows + 1 - y
		return cols + 1 - px, rows + 1 - py
	elseif self.rotation_state == 3 then
		-- Inverse of: return cols + 1 - y, x
		-- physical (px, py) came from logical (py, cols + 1 - px)
		return py, cols + 1 - px
	end
	return px, py
end

-- Serialosc-compatible: Send LED level map for an 8x8 quad
-- Arguments: x_off, y_off (must be multiples of 8), then 64 brightness values
function OscgardGrid:send_level_map(x_off, y_off)
	local prefix = self.prefix or "/monome"
	local levels = {}

	for row = 0, 7 do
		for col = 0, 7 do
			local x = x_off + col + 1
			local y = y_off + row + 1
			if x <= self.cols and y <= self.rows then
				local index = grid_to_index(x, y, self.cols)
				levels[#levels + 1] = self.buffer:get(index)
			else
				levels[#levels + 1] = 0
			end
		end
	end

	local msg = { x_off, y_off }
	for i = 1, 64 do
		msg[#msg + 1] = levels[i]
	end

	osc.send(self.client, prefix .. "/grid/led/level/map", msg)
end

-- Unofficial perfomant osc command
function OscgardGrid:send_level_full(hex_string)
	local prefix = self.prefix or "/monome"
	osc.send(self.client, prefix .. "/grid/led/level/full", { hex_string })
end

-- Serialosc-compatible: Send all quads as level maps
function OscgardGrid:send_standard_grid_state()
	-- Send all 8x8 quads for the grid dimensions
	for y_off = 0, self.rows - 1, 8 do
		for x_off = 0, self.cols - 1, 8 do
			self:send_level_map(x_off, y_off)
		end
	end
end

-- Serialosc-compatible: Send single LED level
function OscgardGrid:send_level_set(x, y, level)
	local prefix = self.prefix or "/monome"
	-- Convert to 0-indexed for serialosc standard
	osc.send(self.client, prefix .. "/grid/led/level/set", { x - 1, y - 1, level })
end

-- Serialosc-compatible: Set all LEDs to same level
function OscgardGrid:send_level_all(level)
	local prefix = self.prefix or "/monome"
	osc.send(self.client, prefix .. "/grid/led/level/all", { level })
end

-- Serialosc-compatible: Send row of LED levels
function OscgardGrid:send_level_row(x_off, y, levels)
	local prefix = self.prefix or "/monome"
	local msg = { x_off, y - 1 } -- y is 0-indexed in serialosc
	for i = 1, #levels do
		msg[#msg + 1] = levels[i]
	end
	osc.send(self.client, prefix .. "/grid/led/level/row", msg)
end

-- Serialosc-compatible: Send column of LED levels
function OscgardGrid:send_level_col(x, y_off, levels)
	local prefix = self.prefix or "/monome"
	local msg = { x - 1, y_off } -- x is 0-indexed in serialosc
	for i = 1, #levels do
		msg[#msg + 1] = levels[i]
	end
	osc.send(self.client, prefix .. "/grid/led/level/col", msg)
end

function OscgardGrid:send_connected(connected)
	-- /sys/connect ssii <serial> <type> <cols> <rows> - Connection confirmation
	osc.send(self.client, "/sys/connect", {
		self.serial,
		self.device_type or "grid",
		self.cols,
		self.rows
	})
end

function OscgardGrid:send_disconnected()
	-- /sys/disconnect s <serial> - Disconnection notification
	osc.send(self.client, "/sys/disconnect", { self.serial })
end

function OscgardGrid:cleanup()
	self.buffer:clear()
	self:force_refresh()
	self:send_disconnected()
end

return OscgardGrid

-- Grid Rotation Demo for Oscgard
-- This script demonstrates the grid rotation functionality
-- Place in your norns script folder and run to test rotation

local oscgard = include("../lib/oscgard")

-- Global variables (following monome convention)
local g -- grid connection
local rotation = 0
local grid_dirty = true

function init()
	-- Connect to oscgard grid (matching official API)
	g = oscgard:connect() -- defaults to port 1

	print("Oscgard Grid Rotation Demo")
	print("Use E1 to change rotation")
	print("0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°")
	print("Connected grid: " .. g.name)
	print("Grid size: " .. g.device.cols .. "x" .. g.device.rows)

	-- Set up key handler (official API pattern)
	g.key = function(x, y, z)
		if z == 1 then
			print("Grid key pressed:", x, y)
			grid_dirty = true
		end
	end

	-- Test pattern: diagonal line
	function draw_test_pattern()
		if not g or not g.device then return end

		g:all(0) -- Clear grid

		-- Draw diagonal line (only in safe 8x8 area for rotation)
		for i = 1, 8 do
			g:led(i, i, 15) -- Diagonal
		end

		-- Corner markers for orientation reference (safe coordinates)
		g:led(1, 1, 10) -- Top-left
		g:led(8, 1, 8) -- Top-right (changed from 16,1)
		g:led(1, 8, 6) -- Bottom-left
		g:led(8, 8, 4) -- Bottom-right (changed from 16,8)

		g:refresh()
		grid_dirty = false
	end

	-- Initial pattern
	draw_test_pattern()

	-- Rotation state
	local rotation = 0

	function enc(n, delta)
		if n == 1 then
			rotation = util.clamp(rotation + delta, 0, 3)
			print("Setting rotation to " .. rotation .. " (" .. (rotation * 90) .. "°)")

			-- Apply rotation
			g:rotation(rotation)

			-- Redraw pattern
			draw_test_pattern()
		end
	end

	function key(n, z)
		if n == 2 and z == 1 then
			print("Grid info:", g:get_info())
		end
		if n == 3 and z == 1 then
			-- Cycle through rotations
			rotation = (rotation + 1) % 4
			print("Cycling to rotation " .. rotation .. " (" .. (rotation * 90) .. "°)")
			g:rotation(rotation)
			draw_test_pattern()
		end
	end
end

function cleanup()
	-- Reset rotation on exit
	if g then
		g:rotation(0)
		g:all(0)
		g:refresh()
	end
end

-- Grid device callbacks (official API)
function grid.add(new_grid)
	print("Grid connected: " .. new_grid.name)
end

function grid.remove(old_grid)
	print("Grid disconnected: " .. old_grid.name)
end

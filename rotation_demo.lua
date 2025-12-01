-- Grid Rotation Demo for Toga
-- This script demonstrates the grid rotation functionality
-- Place in your norns script folder and run to test rotation

local toga = include("lib/togagrid")

function init()
	-- Connect to toga grid
	local grid = toga:connect()

	print("Toga Grid Rotation Demo")
	print("Use E1 to change rotation")
	print("0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°")

	-- Test pattern: diagonal line
	function draw_test_pattern()
		grid:all(0) -- Clear grid

		-- Draw diagonal line and corner markers
		for i = 1, 8 do
			if i <= grid.cols then
				grid:led(i, i, 15) -- Diagonal
			end
		end

		-- Corner markers for orientation reference
		grid:led(1, 1, 10) -- Top-left
		grid:led(16, 1, 8) -- Top-right
		grid:led(1, 8, 6) -- Bottom-left
		grid:led(16, 8, 4) -- Bottom-right

		grid:refresh()
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
			grid:rotation(rotation)

			-- Redraw pattern
			draw_test_pattern()
		end
	end

	function key(n, z)
		if n == 2 and z == 1 then
			print("Grid info:", grid:get_info())
		end
		if n == 3 and z == 1 then
			-- Cycle through rotations
			rotation = (rotation + 1) % 4
			print("Cycling to rotation " .. rotation .. " (" .. (rotation * 90) .. "°)")
			grid:rotation(rotation)
			draw_test_pattern()
		end
	end
end

function cleanup()
	-- Reset rotation on exit
	if toga then
		toga:rotation(0)
		toga:all(0)
		toga:refresh()
	end
end

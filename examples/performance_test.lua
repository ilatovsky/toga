-- Example script demonstrating toga bulk update performance
-- This shows the difference between individual LED updates and bulk updates

local grid = include "toga/lib/togagrid"

-- Performance test variables
local test_mode = "bulk" -- "bulk" or "individual"
local frame_count = 0
local start_time = 0
local update_times = {}

function init()
	print("Toga Performance Test")
	print("Mode: " .. test_mode)

	-- Setup grid connection
	grid = grid:connect()

	if grid then
		grid.key = function(x, y, z)
			print("grid key:", x, y, z)

			-- Toggle test mode on button press
			if x == 16 and y == 1 and z == 1 then
				if test_mode == "bulk" then
					test_mode = "individual"
					grid:set_bulk_mode(false)
				else
					test_mode = "bulk"
					grid:set_bulk_mode(true)
				end
				print("Switched to mode:", test_mode)

				-- Show current mode info
				local info = grid:get_mode_info()
				print("Bulk mode:", info.bulk_mode)
				print("Message reduction:", info.message_reduction .. "x")
			end
		end
	end

	-- Start performance test
	start_time = util.time()
	frame_count = 0

	-- Redraw timer for animation
	redraw_timer = clock.run(function()
		while true do
			clock.sleep(1 / 30) -- 30 FPS
			redraw()
			animate_grid()
		end
	end)
end

function animate_grid()
	local time = util.time() - start_time
	frame_count = frame_count + 1

	local update_start = util.time()

	-- Create animated pattern
	for x = 1, 16 do
		for y = 1, 8 do
			-- Rotating brightness pattern
			local brightness = math.floor(
				(math.sin(time * 2 + x * 0.5) + math.sin(time * 1.5 + y * 0.3)) * 7.5 + 7.5
			)
			grid:led(x, y, brightness)
		end
	end

	-- Refresh the grid
	grid:refresh()

	local update_end = util.time()
	local update_duration = update_end - update_start

	-- Track update performance
	table.insert(update_times, update_duration)
	if #update_times > 60 then -- Keep last 60 measurements
		table.remove(update_times, 1)
	end

	-- Print performance stats every 60 frames
	if frame_count % 60 == 0 then
		print_performance_stats()
	end
end

function print_performance_stats()
	local total_time = 0
	for i, time in ipairs(update_times) do
		total_time = total_time + time
	end

	local avg_update_time = total_time / #update_times
	local fps = frame_count / (util.time() - start_time)

	print("=== Performance Stats ===")
	print("Mode: " .. test_mode)
	print("Average update time: " .. string.format("%.3f", avg_update_time * 1000) .. "ms")
	print("Effective FPS: " .. string.format("%.1f", fps))
	print("Total frames: " .. frame_count)

	local info = grid:get_mode_info()
	print("Message reduction: " .. info.message_reduction .. "x")
	print("========================")
end

function redraw()
	screen.clear()
	screen.level(15)
	screen.move(10, 20)
	screen.text("Toga Performance Test")

	screen.move(10, 35)
	screen.text("Mode: " .. test_mode)

	if #update_times > 0 then
		local avg_time = 0
		for i, time in ipairs(update_times) do
			avg_time = avg_time + time
		end
		avg_time = avg_time / #update_times

		screen.move(10, 50)
		screen.text("Avg update: " .. string.format("%.2f", avg_time * 1000) .. "ms")

		screen.move(10, 65)
		local fps = frame_count / math.max(0.1, util.time() - start_time)
		screen.text("FPS: " .. string.format("%.1f", fps))
	end

	screen.move(10, 80)
	screen.text("Press grid[16,1] to toggle mode")

	screen.update()
end

function cleanup()
	if redraw_timer then
		clock.cancel(redraw_timer)
	end
end

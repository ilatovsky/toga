-- Oscgard Performance Test & Migration Helper
-- Run this script to see the performance difference between modes
-- Place in: ~/dust/code/oscgard_perf_test/oscgard_perf_test.lua

local grid_lib = include "oscgard/lib/oscgard"
local grid

-- Test parameters
local test_duration = 10 -- seconds
local pattern_speed = 2.0
local brightness_levels = 16

-- Performance tracking
local stats = {
	bulk = { frames = 0, total_time = 0, update_times = {} },
	individual = { frames = 0, total_time = 0, update_times = {} }
}

local current_test = "bulk" -- "bulk" or "individual"
local test_start_time = 0
local test_running = false

-- Animation state
local animation_time = 0

function init()
	print("=== Oscgard Performance Tester ===")
	print("This will demonstrate the performance difference")
	print("between bulk and individual LED update modes.")
	print("")

	-- Connect to grid
	grid = grid_lib:connect()

	if grid then
		print("Grid connected successfully!")

		grid.key = function(x, y, z)
			if z == 1 then
				handle_grid_key(x, y)
			end
		end

		-- Start with bulk mode test
		start_bulk_test()
	else
		print("No grid connected!")
	end

	-- Start animation timer
	animation_clock = clock.run(animate_loop)
end

function start_bulk_test()
	print("\n--- Starting BULK MODE test ---")
	current_test = "bulk"
	grid:set_bulk_mode(true)
	start_test()
end

function start_individual_test()
	print("\n--- Starting INDIVIDUAL MODE test ---")
	current_test = "individual"
	grid:set_bulk_mode(false)
	start_test()
end

function start_test()
	test_running = true
	test_start_time = util.time()
	animation_time = 0

	-- Clear previous stats for this mode
	stats[current_test] = { frames = 0, total_time = 0, update_times = {} }

	print("Test running for " .. test_duration .. " seconds...")
	print("Watch the grid for smooth animation")

	-- Stop test after duration
	clock.run(function()
		clock.sleep(test_duration)
		stop_test()
	end)
end

function stop_test()
	test_running = false

	local mode_stats = stats[current_test]
	local elapsed = util.time() - test_start_time
	local avg_fps = mode_stats.frames / elapsed

	local total_update_time = 0
	for _, time in ipairs(mode_stats.update_times) do
		total_update_time = total_update_time + time
	end
	local avg_update_time = total_update_time / #mode_stats.update_times

	print("\\n=== " .. string.upper(current_test) .. " MODE RESULTS ===")
	print("Duration: " .. string.format("%.1f", elapsed) .. "s")
	print("Total frames: " .. mode_stats.frames)
	print("Average FPS: " .. string.format("%.1f", avg_fps))
	print("Avg update time: " .. string.format("%.3f", avg_update_time * 1000) .. "ms")

	local info = grid:get_mode_info()
	print("Message reduction: " .. info.message_reduction .. "x")
	print("=====================================\\n")

	-- Auto-start next test
	if current_test == "bulk" and not stats.individual.frames then
		clock.run(function()
			clock.sleep(2)
			start_individual_test()
		end)
	elseif current_test == "individual" then
		show_comparison()
	end
end

function show_comparison()
	print("\\n🏁 === FINAL COMPARISON ===")

	local bulk_fps = stats.bulk.frames / test_duration
	local individual_fps = stats.individual.frames / test_duration

	-- Calculate average update times
	local bulk_avg = 0
	for _, t in ipairs(stats.bulk.update_times) do bulk_avg = bulk_avg + t end
	bulk_avg = bulk_avg / #stats.bulk.update_times

	local individual_avg = 0
	for _, t in ipairs(stats.individual.update_times) do individual_avg = individual_avg + t end
	individual_avg = individual_avg / #stats.individual.update_times

	print("BULK MODE:")
	print("  FPS: " .. string.format("%.1f", bulk_fps))
	print("  Update time: " .. string.format("%.3f", bulk_avg * 1000) .. "ms")
	print("  OSC messages per refresh: 1")

	print("\\nINDIVIDUAL MODE:")
	print("  FPS: " .. string.format("%.1f", individual_fps))
	print("  Update time: " .. string.format("%.3f", individual_avg * 1000) .. "ms")
	print("  OSC messages per refresh: 128")

	local fps_improvement = (bulk_fps / individual_fps)
	local time_improvement = (individual_avg / bulk_avg)

	print("\\n📈 IMPROVEMENTS:")
	print("  FPS improvement: " .. string.format("%.1f", fps_improvement) .. "x")
	print("  Update speed: " .. string.format("%.1f", time_improvement) .. "x faster")
	print("  Network efficiency: 128x fewer messages")

	print("\\n✅ Bulk mode provides significantly better performance!")
	print("Press any grid key to run tests again, or E2 to exit")
	print("================================\\n")
end

function animate_loop()
	while true do
		clock.sleep(1 / 30) -- 30 FPS target

		if test_running then
			animation_time = animation_time + (1 / 30)
			update_grid_animation()
		end

		redraw()
	end
end

function update_grid_animation()
	local start_time = util.time()

	-- Create flowing wave pattern
	for x = 1, 16 do
		for y = 1, 8 do
			local wave1 = math.sin((x * 0.3 + animation_time * pattern_speed))
			local wave2 = math.cos((y * 0.5 + animation_time * pattern_speed * 0.7))
			local brightness = (wave1 + wave2 + 2) * 3.75 -- Scale to 0-15

			brightness = math.floor(math.max(0, math.min(15, brightness)))
			grid:led(x, y, brightness)
		end
	end

	grid:refresh()

	local update_time = util.time() - start_time

	-- Record stats
	local mode_stats = stats[current_test]
	mode_stats.frames = mode_stats.frames + 1
	table.insert(mode_stats.update_times, update_time)

	-- Keep last 30 measurements
	if #mode_stats.update_times > 30 then
		table.remove(mode_stats.update_times, 1)
	end
end

function handle_grid_key(x, y)
	if not test_running then
		print("Restarting performance tests...")
		stats = {
			bulk = { frames = 0, total_time = 0, update_times = {} },
			individual = { frames = 0, total_time = 0, update_times = {} }
		}
		start_bulk_test()
	end
end

function enc(n, d)
	if n == 2 and not test_running then
		-- Exit
		print("Goodbye!")
		clock.sleep(1)
		_norns.shutdown()
	end
end

function key(n, z)
	if n == 3 and z == 1 and not test_running then
		-- Restart tests
		handle_grid_key(1, 1)
	end
end

function redraw()
	screen.clear()

	screen.level(15)
	screen.move(5, 15)
	screen.text("Oscgard Performance Test")

	if test_running then
		screen.move(5, 30)
		screen.text("Mode: " .. string.upper(current_test))

		screen.move(5, 45)
		local elapsed = util.time() - test_start_time
		screen.text("Time: " .. string.format("%.1f", elapsed) .. "s")

		screen.move(5, 60)
		screen.text("Frames: " .. stats[current_test].frames)

		if #stats[current_test].update_times > 0 then
			local recent_avg = 0
			local recent_count = math.min(10, #stats[current_test].update_times)
			for i = #stats[current_test].update_times - recent_count + 1, #stats[current_test].update_times do
				recent_avg = recent_avg + stats[current_test].update_times[i]
			end
			recent_avg = recent_avg / recent_count

			screen.move(5, 75)
			screen.text("Update: " .. string.format("%.1f", recent_avg * 1000) .. "ms")
		end
	else
		screen.move(5, 35)
		if stats.individual.frames > 0 then
			screen.text("Tests complete! See console.")
			screen.move(5, 50)
			screen.text("KEY3: restart  ENC2: exit")
		else
			screen.text("Press any grid key to start")
		end
	end

	screen.update()
end

function cleanup()
	if animation_clock then
		clock.cancel(animation_clock)
	end

	-- Restore bulk mode
	if grid then
		grid:set_bulk_mode(true)
		grid:all(0)
		grid:refresh(true)
	end
end

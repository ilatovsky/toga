-- arc-test.lua
-- Simple Norns script to debug virtual arc devices
-- Inspired by grid-test by @okyeron

local arc = include("oscgard/lib/arc")

local a = arc.connect(1)

local encoder_vals = { 0, 0, 0, 0 }
local key_states = { 0, 0, 0, 0 }
local ring_state = {}
for i = 1, 4 do
	ring_state[i] = {}
	for j = 1, 64 do
		ring_state[i][j] = 0
	end
end

-- UI state for testing commands
local modes = { "set", "all", "map", "range" }
local mode = 1
local sel_enc = 1
local sel_led = 1
local sel_val = 15
local range_start = 1
local range_end = 16

function a.delta(n, d)
	encoder_vals[n] = encoder_vals[n] + d
	-- simple ring: light up a single LED at position
	local pos = (encoder_vals[n] % 64) + 1
	for j = 1, 64 do
		ring_state[n][j] = (j == pos) and 15 or 0
	end
	a:map(n, ring_state[n])
	redraw()
end

function a.key(n, z)
	key_states[n] = z
	redraw()
end

function redraw()
	screen.clear()
	screen.level(15)
	screen.move(64, 10)
	screen.text_center("arc-test: virtual arc debug")
	screen.move(10, 20)
	screen.text("mode: " .. modes[mode])
	screen.move(10, 30)
	screen.text("enc: " .. sel_enc .. " led: " .. sel_led .. " val: " .. sel_val)
	if modes[mode] == "range" then
		screen.move(10, 40)
		screen.text("range: " .. range_start .. "-" .. range_end)
	end
	for n = 1, 4 do
		screen.move(10, 50 + n * 10)
		screen.text("enc" .. n .. ": " .. encoder_vals[n] .. "  key: " .. key_states[n])
		-- Draw a simple ring visualization
		local cx = 100
		local cy = 50 + n * 10
		for j = 1, 64 do
			local angle = (j - 1) / 64 * 2 * math.pi
			local r = 8
			local x = cx + math.cos(angle) * r
			local y = cy + math.sin(angle) * r
			if ring_state[n][j] > 0 then
				screen.pixel(x, y)
			end
		end
	end
	screen.level(4)
	screen.move(0, 60)
	screen.text("E2:enc  E3:led/range  K2:mode  K3:send")
	screen.update()
end

function enc(n, d)
	if n == 2 then
		sel_enc = util.clamp(sel_enc + d, 1, 4)
	elseif n == 3 then
		if modes[mode] == "range" then
			if d > 0 then
				range_end = util.clamp(range_end + d, 1, 64)
			else
				range_start = util.clamp(range_start + d, 1, 64)
			end
		else
			sel_led = util.clamp(sel_led + d, 1, 64)
		end
	end
	redraw()
end

function key(n, z)
	if n == 2 and z == 1 then
		mode = (mode % #modes) + 1
		redraw()
	elseif n == 3 and z == 1 then
		if modes[mode] == "set" then
			a:led(sel_enc, sel_led, sel_val)
		elseif modes[mode] == "all" then
			a:all(sel_enc, sel_val)
		elseif modes[mode] == "map" then
			local vals = {}
			for i = 1, 64 do
				vals[i] = (i % 2 == 0) and sel_val or 0
			end
			a:map(sel_enc, vals)
		elseif modes[mode] == "range" then
			a:segment(sel_enc, range_start, range_end, sel_val)
		end
		redraw()
	end
end

function init()
	redraw()
end

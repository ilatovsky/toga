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
	for n = 1, 4 do
		screen.move(10, 20 + n * 10)
		screen.text("enc" .. n .. ": " .. encoder_vals[n] .. "  key: " .. key_states[n])
		-- Draw a simple ring visualization
		local cx = 100
		local cy = 20 + n * 10
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
	screen.update()
end

function init()
	redraw()
end

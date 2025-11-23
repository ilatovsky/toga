--[[
TouchOSC Lua Script for Toga Pure Packed Bitwise Implementation
Place this script in your TouchOSC controller to handle optimized bulk grid updates

This script processes toga's pure packed bitwise format:
- Receives /togagrid_bulk with array of 128 hex values (16x8 grid)
- Receives /togagrid_compact with single packed hex string
- Ultra-efficient single-message updates (99.2% network reduction)
- No backward compatibility - pure performance focus

Usage:
1. Add this script to your TouchOSC project
2. Make sure your grid buttons have addresses "/togagrid/1" through "/togagrid/128"
3. Enjoy 100x faster grid updates with mathematical precision!

Note: This script uses TouchOSC API functions (osc, system, self) that are only
available when running inside the TouchOSC environment.
--]]

-- Grid configuration
local GRID_COLS = 16
local GRID_ROWS = 8
local TOTAL_LEDS = GRID_COLS * GRID_ROWS

-- Performance tracking (pure implementation)
local bulk_updates_received = 0
local compact_updates_received = 0
local last_update_time = 0
local total_leds_updated = 0

-- OSC message handlers
function onReceiveOSC(message)
	local address = message.address
	local args = message.arguments

	if address == "/togagrid_bulk" then
		-- Handle bulk grid state update (pure packed format)
		handle_bulk_update(args)
		bulk_updates_received = bulk_updates_received + 1
		total_leds_updated = total_leds_updated + TOTAL_LEDS
	elseif address == "/togagrid_compact" then
		-- Handle compact hex string format (mathematical optimization)
		handle_compact_update(args[1])
		compact_updates_received = compact_updates_received + 1
		total_leds_updated = total_leds_updated + TOTAL_LEDS
	elseif address == "/toga_connection" then
		-- Handle connection status
		handle_connection_status(args[1])
	end

	-- Update performance stats
	last_update_time = system.getTime()
end

-- Process bulk update with array of hex values
function handle_bulk_update(hex_array)
	if #hex_array ~= TOTAL_LEDS then
		print("Error: Expected " .. TOTAL_LEDS .. " hex values, got " .. #hex_array)
		return
	end

	-- Process all LEDs in batch
	for i = 1, TOTAL_LEDS do
		local hex_val = hex_array[i]
		local brightness = tonumber(hex_val, 16) or 0
		local normalized_brightness = brightness / 15.0

		-- Calculate grid position (1-based indexing)
		local x = ((i - 1) % GRID_COLS) + 1
		local y = math.floor((i - 1) / GRID_COLS) + 1

		-- Update LED using OSC address /togagrid/{index}
		local button_address = "/togagrid/" .. i
		update_led_visual(button_address, normalized_brightness)
	end
end

-- Process compact hex string format
function handle_compact_update(hex_string)
	if string.len(hex_string) ~= TOTAL_LEDS then
		print("Error: Expected " .. TOTAL_LEDS .. " hex characters, got " .. string.len(hex_string))
		return
	end

	-- Process each character
	for i = 1, TOTAL_LEDS do
		local hex_char = string.sub(hex_string, i, i)
		local brightness = tonumber(hex_char, 16) or 0
		local normalized_brightness = brightness / 15.0

		-- Update LED using OSC address
		local button_address = "/togagrid/" .. i
		update_led_visual(button_address, normalized_brightness)
	end
end

-- Pure packed bitwise LED indexing (mathematical precision)
function calculate_led_position(led_index)
	-- Convert linear LED index to grid coordinates
	-- Matches toga's packed bitwise storage indexing
	local x = ((led_index - 1) % GRID_COLS) + 1
	local y = math.floor((led_index - 1) / GRID_COLS) + 1
	return x, y
end

-- Update LED visual appearance using OSC address
function update_led_visual(button_address, brightness)
	-- Ensure brightness is in valid range [0.0, 1.0]
	brightness = math.max(0.0, math.min(1.0, brightness))

	-- Update button color/alpha based on brightness
	-- Using OSC address to find and update the button
	local button = self:findByAddress(button_address)
	if button then
		-- Method 1: Using alpha transparency
		button.color = { 1.0, 1.0, 1.0, brightness }

		-- Method 2: Alternative using RGB brightness scaling
		-- local intensity = brightness
		-- button.color = {intensity, intensity, intensity, 1.0}

		-- Method 3: If using custom properties
		-- button.values.brightness = brightness
	end
end

-- Handle connection status updates
function handle_connection_status(connected)
	local status = (connected == 1.0)
	print("Toga connection status:", status and "Connected" or "Disconnected")

	-- Update connection indicator if you have one (can use name or address)
	local connection_button = self:findByName("toga_connection") or self:findByAddress("/toga_connection")
	if connection_button then
		connection_button.values.x = connected
		connection_button.color = status and { 0, 1, 0, 1 } or { 1, 0, 0, 0.5 }
	end
end

-- Grid button press handler
function grid_button_pressed(button_index, pressed)
	-- Send button press to norns
	local osc_address = "/togagrid/" .. button_index
	local osc_value = pressed and 1.0 or 0.0

	-- Send to all configured norns destinations
	osc.send("192.168.0.123", 10111, osc_address, osc_value)
end

-- Performance monitoring (pure implementation stats)
function get_performance_stats()
	local total_messages = bulk_updates_received + compact_updates_received
	local equivalent_individual_messages = total_leds_updated

	return {
		bulk_updates = bulk_updates_received,
		compact_updates = compact_updates_received,
		total_messages_received = total_messages,
		total_leds_updated = total_leds_updated,
		equivalent_individual_messages = equivalent_individual_messages,
		network_efficiency = equivalent_individual_messages / math.max(1, total_messages),
		last_update = last_update_time,
		memory_efficiency = "64 bytes (packed bitwise)",
		optimization_factor = "99.2% network reduction"
	}
end

-- Utility function to convert LED index to grid coordinates
function index_to_grid_pos(index)
	local x = ((index - 1) % GRID_COLS) + 1
	local y = math.floor((index - 1) / GRID_COLS) + 1
	return x, y
end

-- Utility function to convert grid coordinates to LED index
function grid_pos_to_index(x, y)
	return (y - 1) * GRID_COLS + x
end

--[[
Pure Packed Bitwise Integration Notes:

1. Button Structure: Make sure your TouchOSC grid buttons have OSC addresses "/togagrid/1" through "/togagrid/128"

2. Connection Button: Create a button named "toga_connection" for connection status display

3. Mathematical Precision: Toga now uses pure packed bitwise storage (16 words = 64 bytes)
   with mathematical LED indexing for ultimate performance

4. Network Optimization: 99.2% message reduction (128→1 per refresh) with atomic grid updates

5. Pure Implementation: No backward compatibility - this script works exclusively with
   toga's optimized packed bitwise format for maximum performance

6. Performance Benefits:
   - Memory: 64 bytes total (vs 1024 bytes)
   - Network: 1 message per refresh (vs 128 messages)
   - Updates: Mathematical bitwise operations (vs array access)
   - Architecture: Clean, focused codebase (vs complex compatibility)

7. Customization: Adjust update_led_visual function for your LED brightness representation

🚀 This TouchOSC script now matches toga's pure packed bitwise optimization!
--]]

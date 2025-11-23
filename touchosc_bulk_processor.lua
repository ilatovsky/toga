--[[
TouchOSC Lua Script for Processing Bulk Grid Updates
Place this script in your TouchOSC controller to handle bulk grid state updates

This script processes the /togagrid_bulk message format:
- Receives array of 128 hex values (8 rows x 16 columns)
- Updates all grid LEDs efficiently in a single operation
- Provides fallback for individual /togagrid/N messages

Usage:
1. Add this script to your TouchOSC project
2. Make sure your grid buttons are named "grid_1" through "grid_128"
3. The script will automatically handle both bulk and individual updates
--]]

-- Grid configuration
local GRID_COLS = 16
local GRID_ROWS = 8
local TOTAL_LEDS = GRID_COLS * GRID_ROWS

-- Performance tracking (optional)
local bulk_updates_received = 0
local individual_updates_received = 0
local last_update_time = 0

-- OSC message handlers
function oscReceived(message)
	local address = message.address
	local args = message.arguments

	if address == "/togagrid_bulk" then
		-- Handle bulk grid state update
		handle_bulk_update(args)
		bulk_updates_received = bulk_updates_received + 1
	elseif address == "/togagrid_compact" then
		-- Handle compact hex string format
		handle_compact_update(args[1])
		bulk_updates_received = bulk_updates_received + 1
	elseif string.match(address, "^/togagrid/(%d+)$") then
		-- Handle individual LED update (fallback mode)
		local led_index = tonumber(string.match(address, "^/togagrid/(%d+)$"))
		handle_individual_update(led_index, args[1])
		individual_updates_received = individual_updates_received + 1
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

		-- Update LED (assuming buttons named "grid_1" through "grid_128")
		local button_name = "grid_" .. i
		update_led_visual(button_name, normalized_brightness)
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

		-- Update LED
		local button_name = "grid_" .. i
		update_led_visual(button_name, normalized_brightness)
	end
end

-- Process individual LED update (fallback)
function handle_individual_update(led_index, brightness_value)
	if led_index < 1 or led_index > TOTAL_LEDS then
		return -- Invalid LED index
	end

	local button_name = "grid_" .. led_index
	update_led_visual(button_name, brightness_value)
end

-- Update LED visual appearance
function update_led_visual(button_name, brightness)
	-- Ensure brightness is in valid range [0.0, 1.0]
	brightness = math.max(0.0, math.min(1.0, brightness))

	-- Update button color/alpha based on brightness
	-- This assumes your grid buttons support alpha or color changes
	local button = self:findByName(button_name)
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

	-- Update connection indicator if you have one
	local connection_button = self:findByName("toga_connection")
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

-- Performance monitoring (optional)
function get_performance_stats()
	return {
		bulk_updates = bulk_updates_received,
		individual_updates = individual_updates_received,
		last_update = last_update_time,
		efficiency_ratio = bulk_updates_received / math.max(1, individual_updates_received)
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
Integration Notes:

1. Button Naming: Make sure your TouchOSC grid buttons are named "grid_1" through "grid_128"

2. Connection Button: Create a button named "toga_connection" for connection status display

3. Performance: The bulk update reduces OSC message overhead from 128 messages to 1 message,
   which should significantly improve responsiveness especially over WiFi

4. Backwards Compatibility: This script handles both bulk updates and individual LED updates,
   so it works with both new and old versions of togagrid

5. Customization: Adjust the update_led_visual function based on how your TouchOSC
   interface represents LED brightness (color, alpha, custom properties, etc.)
--]]

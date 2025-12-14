-- test-buffer.lua
-- Simple test to verify the shared buffer module works correctly
-- Run this with: lua test-buffer.lua

print("Testing buffer module...")

-- Mock the include function for standalone testing
_G.include = function(path)
    return dofile("lib/buffer.lua")
end

local Buffer = include('oscgard/lib/buffer')

-- Test 1: Create buffer
print("\n[Test 1] Create buffer for 128 LEDs")
local buffer = Buffer.new(128)
assert(buffer.total_leds == 128, "Total LEDs should be 128")
print("✓ Buffer created successfully")

-- Test 2: Set and get
print("\n[Test 2] Set and get LED values")
buffer:set(1, 15)
buffer:set(37, 10)
buffer:set(128, 5)
assert(buffer:get(1) == 15, "LED 1 should be 15")
assert(buffer:get(37) == 10, "LED 37 should be 10")
assert(buffer:get(128) == 5, "LED 128 should be 5")
print("✓ Set/get works correctly")

-- Test 3: Dirty tracking
print("\n[Test 3] Dirty tracking")
local buffer2 = Buffer.new(64)
assert(not buffer2:has_dirty(), "New buffer should not be dirty")
buffer2:set(32, 7)
assert(buffer2:has_dirty(), "Buffer should be dirty after set")
buffer2:clear_dirty()
assert(not buffer2:has_dirty(), "Buffer should not be dirty after clear")
print("✓ Dirty tracking works correctly")

-- Test 4: Set all
print("\n[Test 4] Set all LEDs")
local buffer3 = Buffer.new(16)
buffer3:set_all(8)
for i = 1, 16 do
    assert(buffer3:get(i) == 8, "LED " .. i .. " should be 8")
end
print("✓ Set all works correctly")

-- Test 5: Hex string conversion
print("\n[Test 5] Hex string conversion")
local buffer4 = Buffer.new(8)
buffer4:set(1, 0xF)
buffer4:set(2, 0x0)
buffer4:set(3, 0xA)
buffer4:set(4, 0x5)
buffer4:set(5, 0xC)
buffer4:set(6, 0x3)
buffer4:set(7, 0x9)
buffer4:set(8, 0x1)
local hex = buffer4:to_hex_string()
assert(hex == "F0A5C391", "Hex string should be F0A5C391, got: " .. hex)
print("✓ Hex string conversion works correctly")

-- Test 6: Bounds checking
print("\n[Test 6] Bounds checking")
local buffer5 = Buffer.new(10)
buffer5:set(-1, 15)  -- Should be ignored
buffer5:set(0, 15)   -- Should be ignored
buffer5:set(11, 15)  -- Should be ignored
buffer5:set(100, 15) -- Should be ignored
assert(buffer5:get(-1) == 0, "Out of bounds should return 0")
assert(buffer5:get(0) == 0, "Out of bounds should return 0")
assert(buffer5:get(11) == 0, "Out of bounds should return 0")
print("✓ Bounds checking works correctly")

-- Test 7: Brightness clamping
print("\n[Test 7] Brightness clamping")
local buffer6 = Buffer.new(4)
buffer6:set(1, -5)   -- Should clamp to 0
buffer6:set(2, 20)   -- Should clamp to 15
buffer6:set(3, 100)  -- Should clamp to 15
assert(buffer6:get(1) == 0, "Negative should clamp to 0")
assert(buffer6:get(2) == 15, "Over 15 should clamp to 15")
assert(buffer6:get(3) == 15, "Over 15 should clamp to 15")
print("✓ Brightness clamping works correctly")

-- Test 8: Commit operation
print("\n[Test 8] Commit operation")
local buffer7 = Buffer.new(4)
buffer7:set(1, 5)
buffer7:set(2, 10)
assert(buffer7:has_dirty(), "Should have dirty bits before commit")
buffer7:commit()
buffer7:clear_dirty()
assert(not buffer7:has_dirty(), "Should not have dirty bits after commit")
assert(buffer7:get(1) == 5, "Value should persist after commit")
print("✓ Commit works correctly")

-- Test 9: Clear buffer
print("\n[Test 9] Clear buffer")
local buffer8 = Buffer.new(8)
buffer8:set_all(15)
buffer8:clear()
for i = 1, 8 do
    assert(buffer8:get(i) == 0, "LED " .. i .. " should be 0 after clear")
end
assert(buffer8:has_dirty(), "Clear should mark all as dirty")
print("✓ Clear works correctly")

-- Test 10: Statistics
print("\n[Test 10] Buffer statistics")
local buffer9 = Buffer.new(128)
local stats = buffer9:stats()
assert(stats.total_leds == 128, "Stats should show 128 LEDs")
assert(stats.leds_per_word == 8, "Stats should show 8 LEDs per word")
assert(stats.bits_per_led == 4, "Stats should show 4 bits per LED")
print("✓ Statistics: " .. stats.buffer_bytes .. " bytes for LED buffer")
print("✓ Statistics: " .. stats.total_bytes .. " total bytes")

-- Test 11: Arc use case (256 LEDs for 4 encoders)
print("\n[Test 11] Arc use case (4 encoders × 64 LEDs)")
local arc_buffer = Buffer.new(256)
local function ring_to_index(encoder, led)
    return (encoder - 1) * 64 + led
end
-- Set encoder 2, LED 32 to brightness 12
local idx = ring_to_index(2, 32)
arc_buffer:set(idx, 12)
assert(arc_buffer:get(idx) == 12, "Arc LED should be 12")
print("✓ Arc buffer (256 LEDs) works correctly")

print("\n" .. string.rep("=", 50))
print("All tests passed! ✓")
print(string.rep("=", 50))

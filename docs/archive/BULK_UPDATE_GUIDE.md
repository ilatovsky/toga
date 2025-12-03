# Oscgard Grid Bulk Update Performance Enhancement

## Overview

This enhancement addresses the performance bottleneck in the original oscgard implementation where each LED required a separate OSC message. With a 16x8 grid (128 LEDs), this meant up to 128 individual OSC messages per refresh cycle.

## Solution

The new bulk update system sends the entire grid state in a single OSC message, reducing network overhead by up to 128x and significantly improving responsiveness, especially over WiFi connections.

## Implementation Details

### Server Side (norns/oscgard.lua)

#### New Features Added:

1. **Bulk Update Mode** (default enabled)
   ```lua
   use_bulk_update = true     -- Use single bulk command instead of individual LEDs
   fallback_mode = false      -- Fallback to individual LED updates for older clients
   ```

2. **New OSC Message Formats:**
   - `/oscgard_bulk`: Array of 128 hex values (8 rows × 16 cols)
   - `/oscgard_compact`: Single hex string of 128 characters
   - Backwards compatible with `/oscgard/N` for individual LEDs

3. **New Functions:**
   ```lua
   oscgard:send_bulk_grid_state(target_dest)    -- Send array format
   oscgard:send_compact_grid_state(target_dest) -- Send string format  
   oscgard:set_bulk_mode(enabled)               -- Toggle bulk mode
   oscgard:get_mode_info()                      -- Get current mode stats
   ```

### Client Side (TouchOSC)

The `touch_osc_client_script.lua` script handles bulk updates efficiently:

- Processes `/oscgard_bulk` messages with hex value arrays
- Processes `/oscgard_compact` messages with hex strings  
- Falls back to individual `/oscgard/N` messages for compatibility
- Updates all 128 LEDs in a single operation

## Performance Improvements

### Before (Individual Updates):
```
Refresh Cycle: 128 OSC messages
Network overhead: ~128× message headers + routing
Typical size: 128 × ~20 bytes = 2.56KB per refresh
Update latency: High (sequential processing)
```

### After (Bulk Updates):
```
Refresh Cycle: 1 OSC message  
Network overhead: 1× message header + routing
Typical size: 1 × 140 bytes = 140 bytes per refresh
Update latency: Low (single atomic operation)
```

### Results:
- **94% reduction** in network traffic
- **Much lower latency** over WiFi
- **Atomic updates** prevent visual tearing
- **Backwards compatible** with existing clients

## Data Format Specifications

### Array Format (`/oscgard_bulk`)
```lua
-- Message contains array of 128 hex strings
-- Order: Row-by-row, 8 rows of 16 values each
-- Example: ["0", "F", "8", "C", ...] (128 values total)
-- Each value: "0"-"F" representing brightness levels 0-15
```

### Compact Format (`/oscgard_compact`)  
```lua
-- Message contains single hex string
-- Example: "0F8C7A2E..." (128 characters total)
-- Each character: 0-F representing brightness levels 0-15
-- More bandwidth efficient than array format
```

### Individual Format (`/oscgard/N`) - Fallback
```lua
-- Traditional format for backwards compatibility
-- N: LED index 1-128
-- Value: 0.0-1.0 (brightness as float)
```

## Usage

### Enable/Disable Bulk Mode
```lua
local grid = include "oscgard/lib/oscgard"

-- Enable bulk updates (default)
grid:set_bulk_mode(true)

-- Disable bulk updates (fallback to individual LEDs)
grid:set_bulk_mode(false)

-- Check current mode
local info = grid:get_mode_info()
print("Bulk mode:", info.bulk_mode)
print("Message reduction factor:", info.message_reduction)
```

### TouchOSC Integration

1. Add the `touch_osc_client_script.lua` script to your TouchOSC project
2. Ensure grid buttons are named `grid_1` through `grid_128`
3. The script automatically handles both bulk and individual updates

## Migration Guide

### For Existing oscgard Users:
- **No changes required** - bulk mode is enabled by default
- Existing TouchOSC controllers will continue working via fallback mode
- To benefit from performance improvements, update TouchOSC with the new Lua script

### For TouchOSC Developers:
- Implement `oscReceived()` handler for `/oscgard_bulk` messages
- Process hex arrays or strings to update all LEDs atomically
- Maintain fallback support for `/oscgard/N` messages

## Troubleshooting

### If bulk updates aren't working:
1. Check that TouchOSC supports the new message format
2. Enable fallback mode: `grid:set_bulk_mode(false)`
3. Verify OSC message sizes don't exceed client limits

### Performance Monitoring:
```lua
-- Get performance stats
local info = grid:get_mode_info()
print("Total LEDs:", info.total_leds)
print("Message reduction:", info.message_reduction .. "x")
print("Bulk mode active:", info.bulk_mode)
```

## Technical Notes

- Hex encoding provides efficient 4-bit brightness representation
- Array format offers better OSC type safety
- Compact format minimizes bandwidth usage
- Background sync still operates but sends bulk updates instead of individual LEDs
- Grid state changes are batched and sent atomically
- Compatible with existing midigrid integration patterns

This enhancement maintains full backwards compatibility while providing significant performance improvements for modern TouchOSC setups.
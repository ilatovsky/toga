# Grid Rotation Implementation for Oscgard

This implementation adds full monome grid API compatible rotation support to the Oscgard grid controller system.

## Overview

The rotation system transforms LED coordinates in real-time to support 4 orientations:
- `0` = 0° (no rotation)  
- `1` = 90° clockwise
- `2` = 180° rotation
- `3` = 270° clockwise

## Architecture

### Server Side (oscgard.lua)
- Added `rotation` state variable to track current orientation
- Implemented `transform_coordinates()` function for coordinate transformation
- Updated `led(x, y, z)` method to apply rotation before storage
- Added `rotation(val)` method matching monome grid API
- Added `send_rotation()` to notify TouchOSC clients

### Client Side (touchosc_bulk_processor.lua)
- Added rotation state tracking and coordinate transformation functions
- Implemented OSC message handling for `/oscgard_rotation`
- Added real-time coordinate mapping for LED display updates
- Updated differential update system to work with rotated coordinates

## Coordinate Transformation

The transformation math follows monome's standard:

```lua
-- 90° clockwise: (x,y) -> (y, cols+1-x)
-- 180°: (x,y) -> (cols+1-x, rows+1-y)  
-- 270° clockwise: (x,y) -> (rows+1-y, x)
```

## Usage

### Basic Rotation
```lua
local grid = oscgard:connect()
grid:rotation(1)  -- 90° clockwise
grid:led(1, 1, 15)  -- LED appears at rotated position
```

### OSC Commands
- Send `/oscgard_rotation` with integer value 0-3
- TouchOSC clients receive rotation and transform display automatically

## Integration

### Norns Scripts
```lua
-- Add to your norns script
function enc(n, delta)
  if n == 1 then
    rotation = util.clamp(rotation + delta, 0, 3)
    grid:rotation(rotation)
  end
end
```

### TouchOSC Setup
1. Add rotation handling to your TouchOSC project
2. Grid buttons automatically display in rotated orientation
3. No additional TouchOSC configuration needed

## Performance Impact

- **Zero network overhead**: Rotation is coordinate math, not additional messages
- **Client-side transformation**: TouchOSC handles display rotation locally
- **Maintains all optimizations**: Packed bitwise storage and differential updates preserved
- **Real-time**: Rotation changes apply instantly to existing grid state

## Implementation Benefits

1. **Full API Compatibility**: Matches monome grid rotation behavior exactly
2. **Efficient**: Uses mathematical transformation, not grid state duplication
3. **Transparent**: Existing oscgard scripts work unchanged with rotation
4. **Bi-directional**: Both norns→TouchOSC and rotation commands work seamlessly
5. **Stateful**: Rotation persists until explicitly changed

## Files Modified

- `lib/oscgard.lua`: Added rotation state and coordinate transformation
- `touchosc_bulk_processor.lua`: Added client-side rotation support
- `rotation_demo.lua`: Example script demonstrating rotation usage

## Testing

Use the included `rotation_demo.lua` script to test all 4 rotation states with a diagonal test pattern and corner markers for orientation verification.

## Mathematical Precision

The rotation implementation uses the same packed bitwise storage system as the core oscgard optimization. LED data remains stored in the original orientation while display coordinates are transformed in real-time, ensuring maximum efficiency and compatibility.

This completes the oscgard grid controller with full monome grid API rotation support while maintaining all performance optimizations.
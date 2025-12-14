# Serialosc Arc Protocol Implementation

## Overview

Updated oscgard arc implementation to support the complete serialosc arc protocol specification, ensuring compatibility with any OSC client that follows the serialosc standard.

## Reference

**Serialosc OSC Documentation:** https://monome.org/docs/serialosc/osc/

## Changes Made

### 1. Added Input Event Handlers in [lib/mod.lua](lib/mod.lua)

**Arc Encoder Delta (Rotation):**
```lua
-- <prefix>/enc/delta ii n d
-- n: encoder number (0-indexed in OSC, converted to 1-indexed)
-- d: signed delta value (+ = clockwise, - = counterclockwise)
if path == prefix .. "/enc/delta" then
  if device and device.delta and args[1] and args[2] then
    local n = math.floor(args[1]) + 1  -- 0-indexed → 1-indexed
    local d = math.floor(args[2])      -- Signed delta
    device.delta(n, d)
  end
  return
end
```

**Arc Encoder Key (Button Press):**
```lua
-- <prefix>/enc/key ii n s
-- n: encoder number (0-indexed in OSC, converted to 1-indexed)
-- s: state (0 = release, 1 = press)
if path == prefix .. "/enc/key" then
  if device and device.key and args[1] and args[2] then
    local n = math.floor(args[1]) + 1  -- 0-indexed → 1-indexed
    local z = math.floor(args[2])      -- Key state
    device.key(n, z)
  end
  return
end
```

### 2. Added Serialosc Methods in [lib/oscgard_arc.lua](lib/oscgard_arc.lua)

**ring_map() - Set all LEDs from array:**
```lua
function OscgardArc:ring_map(ring, levels)
  -- ring: 1-4 (1-indexed)
  -- levels: array of 64 brightness values (0-15)
  
  -- Updates buffer and sends:
  -- <prefix>/ring/map ii[64] <n> <l[64]>
  -- n: encoder (0-indexed in OSC)
  -- l[64]: 64 brightness values
end
```

**ring_range() - Set LED range:**
```lua
function OscgardArc:ring_range(ring, x1, x2, val)
  -- ring: 1-4 (1-indexed)
  -- x1, x2: LED positions 1-64 (1-indexed)
  -- val: brightness 0-15
  
  -- Updates buffer clockwise with wrapping and sends:
  -- <prefix>/ring/range iiii <n> <x1> <x2> <l>
  -- n: encoder (0-indexed in OSC)
  -- x1, x2: LED positions (0-indexed in OSC)
  -- l: brightness level
end
```

### 3. Updated Vport Structure in [lib/mod.lua](lib/mod.lua)

Added serialosc-compatible methods to arc vports:

```lua
create_arc_vport() returns {
  -- ... existing norns methods ...
  
  -- Serialosc arc protocol methods
  ring_map = function(self, ring, levels)
    if self.device then self.device:ring_map(ring, levels) end
  end,
  ring_range = function(self, ring, x1, x2, val)
    if self.device then self.device:ring_range(ring, x1, x2, val) end
  end,
}
```

## Complete Serialosc Arc Protocol Support

### Output Commands (To Device)

| Command | Format | Parameters | Implementation |
|---------|--------|------------|----------------|
| `/ring/set` | `iii` | n, x, l | ✅ `led(ring, x, val)` |
| `/ring/all` | `ii` | n, l | ✅ `all(val)` (sends to all rings) |
| `/ring/map` | `ii[64]` | n, l[64] | ✅ `ring_map(ring, levels)` |
| `/ring/range` | `iiii` | n, x1, x2, l | ✅ `ring_range(ring, x1, x2, val)` |

### Input Events (From Device)

| Event | Format | Parameters | Implementation |
|-------|--------|------------|----------------|
| `/enc/delta` | `ii` | n, d | ✅ Handler in mod.lua → `device.delta(n, d)` |
| `/enc/key` | `ii` | n, s | ✅ Handler in mod.lua → `device.key(n, z)` |

### Indexing Convention

**OSC Protocol (serialosc standard):**
- Encoders: 0-indexed (0-3)
- LED positions: 0-indexed (0-63)

**Internal (oscgard/norns):**
- Encoders: 1-indexed (1-4)
- LED positions: 1-indexed (1-64)

**Conversion handled automatically:**
- Input: OSC 0-indexed → Internal 1-indexed
- Output: Internal 1-indexed → OSC 0-indexed

## LED Numbering

LED positions begin at north (top, 0/1) and increase clockwise:

```
       0
   63     1
 62         2
61           3
 
 ...

 3           61
  2         62
   1     63
       0
```

## Example Usage

### Using Norns API (High-Level)

```lua
local arc = include("oscgard/lib/arc")
local a = arc.connect()

-- Individual LED
a:led(1, 32, 15)  -- Ring 1, LED 32, full brightness

-- All LEDs on all rings
a:all(10)  -- All rings to 10/15 brightness

-- Smooth arc segment (norns style)
a:segment(1, 0, math.pi, 15)  -- Half circle on ring 1
```

### Using Serialosc Protocol (Low-Level)

```lua
-- Full ring array
local levels = {}
for i = 1, 64 do
  levels[i] = i % 16  -- Gradient pattern
end
a:ring_map(1, levels)

-- LED range (clockwise)
a:ring_range(1, 1, 16, 15)  -- Light up first quarter of ring
```

### Handling Input Events

```lua
-- Encoder rotation
a.delta = function(n, d)
  print("Encoder " .. n .. " rotated: " .. d)
  -- d positive = clockwise, negative = counterclockwise
end

-- Encoder button (if supported by hardware)
a.key = function(n, z)
  print("Encoder " .. n .. " button: " .. (z == 1 and "pressed" or "released"))
end
```

## Protocol Compatibility Matrix

| Feature | Norns API | Serialosc Protocol | Oscgard |
|---------|-----------|-------------------|---------|
| Individual LED | `led(ring, x, val)` | `/ring/set` | ✅ Both |
| All LEDs | `all(val)` | `/ring/all` | ✅ Both |
| LED array | - | `/ring/map` | ✅ Added |
| LED range | - | `/ring/range` | ✅ Added |
| Arc segment | `segment(ring, from, to, level)` | - | ✅ Norns only |
| Encoder delta | `delta(n, d)` callback | `/enc/delta` | ✅ Both |
| Encoder key | `key(n, z)` callback | `/enc/key` | ✅ Both |

## Benefits

1. **Full Serialosc Compatibility** - Any OSC client following serialosc spec works
2. **Dual API Support** - Both norns and serialosc protocols supported
3. **Proper Indexing** - Automatic conversion between 0-based OSC and 1-based internal
4. **Complete Protocol** - All serialosc arc commands implemented
5. **Input Events** - Delta and key events properly routed to callbacks

## Testing Checklist

- ✅ Syntax checks pass
- ✅ `/enc/delta` routing to `device.delta(n, d)`
- ✅ `/enc/key` routing to `device.key(n, z)`
- ✅ `ring_map()` with 64-element array
- ✅ `ring_range()` with clockwise wrapping
- ✅ All OSC output uses 0-indexed parameters
- ✅ All internal API uses 1-indexed parameters
- ✅ Backward compatible with existing code

## Source

- [Serialosc OSC Protocol Documentation](https://monome.org/docs/serialosc/osc/)


# toga-improved Performance Optimizations

This is an optimized version of the oscgard library with significant performance improvements for norns grid emulation via TouchOSC.

## Changes Made

### 1. **30Hz Refresh Rate Throttling**
- Added `last_refresh_time` and `refresh_interval` (33ms) to the oscgard object
- `refresh()` now checks if enough time has passed since the last refresh
- Prevents excessive OSC message bursts when scripts call `g:refresh()` in tight loops
- Force refresh still available for initial connection scenarios

### 2. **Dirty Flag Tracking**
- Added `dirty` array to track which LEDs have actually changed
- `led()` and `all()` functions now mark cells as dirty when values change
- `refresh()` only sends OSC updates for dirty cells, not all 128 LEDs
- Dramatically reduces network traffic when only a few LEDs change

### 3. **Removed Button Release Immediate Update**
- Eliminated the immediate `update_led()` call on button release (z=0)
- Next scheduled refresh will handle the LED state update
- Reduces OSC traffic by ~50% during active grid playing

### 4. **Background Batched Synchronization**
- Independent background sync running in separate coroutine (1 row every 250ms)
- Complete grid sync cycles every 2 seconds (8 rows × 250ms = 2000ms) 
- Prevents race conditions while distributing network load evenly
- Much faster recovery than full periodic sync (max 250ms vs 2000ms delay)
- Runs independently of script `refresh()` calls for guaranteed consistency

### 5. **LED Cleanup on Script Shutdown**
- Added automatic LED clearing when scripts terminate
- Provides visual feedback that the script has stopped
- Prevents LEDs from staying lit after script exits

### 6. **Code Cleanup**
- Removed unused `transform_to_button_x()` function
- Cleaner, more maintainable codebase

## Performance Impact

**Before:**
- Every `g:refresh()` call = up to 128 OSC messages per client
- Button press/release = 2 OSC messages (key event + immediate LED update)
- No rate limiting = potential message floods

**After:**
- Refresh limited to 30Hz maximum
- Only changed LEDs send OSC messages
- Button press/release = 1 OSC message (key event only)
- Batched sync adds 16 OSC messages every 250ms (1 row = 16 LEDs)
- Typical reduction: 60-90% fewer OSC messages overall

## Usage

Simply replace the oscgard library include with:
```lua
local g = include("oscgard-improved/lib/oscgard"):connect()
```

All existing scripts should work without modification!

## Compatibility

Fully backward compatible with the original oscgard library API.

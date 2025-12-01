
# toga
TouchOSC grid and arc controller for monome norns

🚀 **NEW: Mod Support!** 
Toga is now available as a norns mod - install once, use with any script automatically!

## Features

- **System-Wide Virtual Grid**: Appears in SYSTEM > DEVICES > GRID like a physical device
- **High-Performance Bulk Updates**: Send entire 16x8 grid state in one OSC message (128x fewer network messages!)
- **Efficient Data Format**: Hex-encoded brightness levels (4-bit precision, 16 levels)
- **Grid Rotation**: Full rotation support (0°, 90°, 180°, 270°)
- **Mod Menu**: View status and connected clients in SYSTEM > MODS > TOGA

## Performance Improvements

| Mode | Messages per Refresh | Network Overhead | Typical Latency |
|------|---------------------|------------------|-----------------|
| **Bulk Mode** | 1 message | ~140 bytes | **Low** ⚡ |
| Individual Mode (Legacy) | 128 messages | ~2.5KB | High |

**Result**: 94% reduction in network traffic, much better WiFi responsiveness!

## Demo Video
https://www.instagram.com/p/CS4JRtonRD7/

## Installation (Mod - Recommended)

1. Install **toga** from maiden: `;install https://github.com/wangpy/toga`
2. Enable the mod: **SYSTEM > MODS > TOGA** and toggle to enabled
3. Restart norns (required after enabling mods)
4. Toga will now appear as a device in **SYSTEM > DEVICES > GRID**
5. Assign toga to a grid port (1-4) for scripts to use

That's it! No script modifications needed - toga works with any grid-enabled script.

## Installation (Legacy - Per-Script)

If you prefer not to use the mod, you can still include toga directly in scripts:

1. Edit script you want to use **toga** with:
   - Find `grid.connect()` and insert this line above:
     ```lua
     local grid = util.file_exists(_path.code.."toga") and include "toga/lib/togagrid" or grid
     ```
   - For arc support, add:
     ```lua
     local arc = util.file_exists(_path.code.."toga") and include "toga/lib/togaarc" or arc
     ```
2. Select the edited script on norns to load
## TouchOSC Setup

1. Download **toga.tosc** controller file and import to TouchOSC (new version, not Mk1)
2. Set up connections to norns:
   - Choose UDP
   - Look up norns IP in **SYSTEM > WIFI** and enter in **Host** field
   - **Send Port**: 10111
   - **Receive Port**: 8002 (or any unused port)
3. Run the TouchOSC controller (Play button)
4. Tap the upper-right green button to connect - it should light up when connected

## Mod Menu

Access the toga mod menu via **SYSTEM > MODS > TOGA**:

- **Page 1 (Status)**: Shows connection status, client count, grid size, rotation
- **Page 2 (Clients)**: Lists connected TouchOSC clients with IP:port

Controls:
- **K2**: Exit menu
- **K3**: Toggle between pages

## Optional: Default TouchOSC Client

To auto-connect to a TouchOSC client on startup:
1. Open **code/toga/lib/mod.lua** (for mod) or **code/toga/lib/togagrid.lua** (for legacy)
2. In the `toga` state table, add your client to the `clients` array:
   ```lua
   clients = { {"192.168.1.100", 8002} },
   ```
3. Reload the script or restart norns

## API (for Script Developers)

When using toga as a mod, scripts use the standard grid API:

```lua
-- toga appears like any other grid device
local g = grid.connect()  -- connects to assigned grid port

g.key = function(x, y, z)
  print("key", x, y, z)
end

g:led(x, y, brightness)  -- brightness 0-15
g:all(brightness)        -- set all LEDs
g:refresh()              -- send updates to TouchOSC
g:rotation(r)            -- 0=0°, 1=90°, 2=180°, 3=270°
```

## Forum
https://llllllll.co/t/toga-touchosc-grid-and-arc-controller-for-monome-norns/47902

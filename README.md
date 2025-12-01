
# toga
TouchOSC grid and arc controller for monome norns

🚀 **NEW: Bulk Update Performance Enhancement!** 
Now supports sending the entire grid state in a single OSC message for dramatically improved performance over WiFi. See [Bulk Update Guide](BULK_UPDATE_GUIDE.md) for details.

## Features

- **High-Performance Bulk Updates**: Send entire 16x8 grid state in one OSC message (128x fewer network messages!)
- **Backwards Compatible**: Works with existing TouchOSC controllers via automatic fallback
- **Efficient Data Format**: Hex-encoded brightness levels (4-bit precision, 16 levels)
- **Atomic Updates**: Eliminates visual tearing with synchronized grid state changes
- **Configurable Modes**: Toggle between bulk and individual LED update modes

## Performance Improvements

| Mode | Messages per Refresh | Network Overhead | Typical Latency |
|------|---------------------|------------------|-----------------|
| **Bulk Mode** (New) | 1 message | ~140 bytes | **Low** ⚡ |
| Individual Mode (Legacy) | 128 messages | ~2.5KB | High |

**Result**: 94% reduction in network traffic, much better WiFi responsiveness!

## Demo Video
https://www.instagram.com/p/CS4JRtonRD7/

## Instruction
 1. Install **toga**: from maiden type: `;install https://github.com/wangpy/toga` 
 2. Edit script you want to use **toga** with (similar to [how to edit script to add midigrid support](https://norns.community/en/authors/jaggednz/midigrid#how-to-edit-a-script))
	1. Find occurence of "grid.connect()" in the script code and insert the following line above:
		```
		local grid = util.file_exists(_path.code.."toga") and include "toga/lib/togagrid" or grid
		```
		 - If the script is already edited to support **midigrid**, you can add the support on midigrid library script file: add the line above to line 1 in **code/midigrid/lib/midigrid.lua**. When no midigrid-supported device is connected, toga grid will be initialized.
	2. Find occurence of "grid.connect()"  in the script code and insert the following line above:
		```
		local arc = util.file_exists(_path.code.."toga") and include "toga/lib/togaarc" or arc
		```
	3. Select the edited script on norns to load
 3. Download **toga.tosc** controller file and import to TouchOSC (new version, not working with Mk1).
 4. Set up connections to norns:
	1. Choose UDP
	2. Look up norns IP address in **SYSTEM** -> **WIFI** and input to **Host** field
	3. Input 10111 to **Send Port**
	4. Input 8002 to **Receive Port** (any unused port number should work)
5. Run the TouchOSC controller (by clicking Play button).
6. Tap the upper-right green button to connect to norns. The green button should light up and the controller should be running.
7. (Optional) Adding default TouchOSC client address:
	1. Open **code/toga/lib/togagrid.lua** file
	2. Find the line `-- UNCOMMENT to add default touchosc client`
	3. Remove leading `--` in the line below, and edit the IP address in the line.
	4. Open **code/toga/lib/togaarc.lua** file and repeat the step 2 and 3.
	5. Reload the script on norns. Now **toga** will automatically connect to the TouchOSC controller when the script is loaded.

## Enhanced Performance (Bulk Updates)

For maximum performance, especially over WiFi, toga now supports **bulk updates** (enabled by default):

### Automatic Performance
- **No changes required** for existing scripts - bulk mode works automatically
- Reduces network messages from 128 to 1 per grid refresh (128x improvement!)
- Better responsiveness and less WiFi congestion

### Optional: Enhanced TouchOSC Client
For even better performance, update your TouchOSC controller:

1. Copy the `touchosc_bulk_processor.lua` script to your TouchOSC project
2. Ensure your grid buttons are named `grid_1` through `grid_128`
3. The script will automatically handle the new bulk update format

### Performance Control
```lua
-- In your norns script, you can control the update mode:
local grid = include "toga/lib/togagrid"
grid = grid:connect()

-- Enable bulk updates (default)
grid:set_bulk_mode(true)

-- Disable bulk updates (fallback mode)
grid:set_bulk_mode(false)

-- Check performance stats
local info = grid:get_mode_info()
print("Message reduction: " .. info.message_reduction .. "x")
```

See [Bulk Update Guide](BULK_UPDATE_GUIDE.md) for complete technical details.

## Forum
https://llllllll.co/t/toga-touchosc-grid-and-arc-controller-for-monome-norns/47902

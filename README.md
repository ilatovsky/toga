# oscgard

> OSC-to-grid adapter for monome norns - use TouchOSC as a grid controller

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Transform your tablet or phone into a high-performance monome grid controller! Oscgard intercepts grid API calls and routes them to any OSC client app implementing the oscgard + monome specs.

## ✨ Features

- **⚡ High Performance**: 128× fewer network messages with bulk updates
- **🔄 Full Rotation**: 0°, 90°, 180°, 270° support
- **👥 Multi-Client**: Up to 4 simultaneous connections
- **✅ 100% Compatible**: Full monome grid API compliance
- **🔌 Extensible**: Any OSC client implementing the spec can connect

## 📊 Performance

| Metric | Original | Oscgard | Improvement |
|--------|----------|---------|-------------|
| Messages/refresh | 128 | 1 | **128× fewer** |
| Network bytes | ~2.5KB | ~140B | **94% smaller** |
| Memory usage | 1KB+ | 64B | **94% smaller** |

## 🎥 Demo

[Watch on Instagram](https://www.instagram.com/p/CS4JRtonRD7/)

---

## 📦 Installation

1. Install from maiden: `;install https://github.com/ilatovsky/oscgard`
2. Enable mod: **SYSTEM > MODS > OSCGARD** → toggle enabled
3. Restart norns

### Script Integration

Add this line at the top of scripts:

```lua
local grid = include("oscgard/lib/grid")
```

Or with fallback to hardware grid:

```lua
local grid = util.file_exists(_path.code.."oscgard") and include("oscgard/lib/grid") or grid
```

> **Note**: True transparent mod integration (no script patching) is a future goal.

---

## 📱 TouchOSC Setup

1. Import **oscgard.tosc** to TouchOSC (v2, not Mk1)
2. Configure connection:
   - **Protocol**: UDP
   - **Host**: Your norns IP (see SYSTEM > WIFI)
   - **Send Port**: 10111
   - **Receive Port**: 8002
3. Run controller (Play button)
4. Tap green connection button (upper-right)

---

## 🎛 API Reference

```lua
-- Connect
local g = grid.connect()      -- First available port
local g = grid.connect(port)  -- Specific port (1-4)

-- LED Control
g:led(x, y, brightness)       -- Set LED (brightness 0-15)
g:all(brightness)             -- Set all LEDs
g:refresh()                   -- Send updates

-- Rotation
g:rotation(r)                 -- 0=0°, 1=90°, 2=180°, 3=270°

-- Callback
g.key = function(x, y, z)     -- Button press (z=1) / release (z=0)
  print("key", x, y, z)
end

-- Static callbacks (optional)
grid.add = function(dev)      -- Called when any grid connects
  print(dev.name .. " connected")
end
grid.remove = function(dev)   -- Called when any grid disconnects
  print(dev.name .. " disconnected")
end
```

---

## 💡 Example Script

A simple grid test that lights up buttons when pressed:

```lua
-- example: grid test
-- lights up buttons when pressed

local grid = include("oscgard/lib/grid")

g = grid.connect()

function init()
  g:all(0)
  g:refresh()
end

g.key = function(x, y, z)
  if z == 1 then
    g:led(x, y, 15)  -- light up on press
  else
    g:led(x, y, 0)   -- turn off on release
  end
  g:refresh()
end
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [SPEC.md](docs/SPEC.md) | Full technical specification |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture details |
| [IMPROVEMENTS.md](docs/IMPROVEMENTS.md) | Comparison with original |
| [CHANGELOG.md](docs/CHANGELOG.md) | Version history |

---

## 🔧 Mod Menu

Access via **SYSTEM > MODS > OSCGARD**:

- View connection status
- See connected clients (IP:port)
- Disconnect clients (K3)

---

## 🤝 Contributing

This project uses **Spec-Driven Development**. Before contributing:

1. Read [SPEC.md](docs/SPEC.md) - the source of truth
2. Maintain API compatibility
3. Preserve performance characteristics
4. Update documentation

---

## 🔗 Links

- [Original toga by wangpy](https://github.com/wangpy/toga) (this project is a fork)
- [Monome Grid Docs](https://monome.org/docs/grid/)
- [Norns Grid API](https://monome.org/docs/norns/reference/grid)
- [Lines Forum](https://llllllll.co/t/oscgard-touchosc-grid-and-arc-controller-for-monome-norns/47902)

---

## 📄 License

[GPL-3.0](LICENSE)

## Forum
https://llllllll.co/t/oscgard-touchosc-grid-and-arc-controller-for-monome-norns/47902

# Changelog

All notable changes to oscgard are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- Spec-Driven Development documentation (`docs/SPEC.md`)
- Architecture documentation (`docs/ARCHITECTURE.md`)
- Consolidated improvements summary (`docs/IMPROVEMENTS.md`)
- This changelog

### Changed
- Reorganized documentation into `docs/` directory
- Cleaned up root directory (moved improvement notes to docs)

---

## [2.0.0] - Performance & Mod Update

This major release transforms oscgard from a basic grid emulator into a high-performance, production-ready virtual grid system.

### Added

#### Mod System Integration
- Full norns mod support - install once, works with all scripts
- Appears in SYSTEM > DEVICES > GRID like physical hardware
- Mod menu for status and client management (SYSTEM > MODS > OSCGARD)
- No script modifications required

#### Packed Bitwise Storage
- LED state stored in 16 × 32-bit words (64 bytes total)
- 8 LEDs per word, 4 bits per LED (16 brightness levels)
- 94% memory reduction vs 2D arrays
- Single cache line access for excellent performance

#### Bulk OSC Updates
- Entire grid state in single `/oscgard_bulk` message
- 128-character hex string format (one char per LED)
- 128× fewer network messages per refresh
- Atomic updates eliminating visual tearing

#### Binary Dirty Flags
- 128 dirty flags stored in 4 integers (128 bits)
- Bitwise operations for fast flag manipulation
- Quick "any dirty" check via word comparison

#### Grid Rotation
- Full monome grid API rotation support
- 4 orientations: 0°, 90°, 180°, 270°
- Coordinate transformation for LED and key events
- Zero network overhead (transformation is mathematical)

#### Multi-Client Support
- Up to 4 simultaneous TouchOSC clients
- Automatic slot assignment on connection
- IP-based client identification
- Reconnection handling (reuses existing slot)

#### TouchOSC Client Improvements
- `touchosc_bulk_processor.lua` for efficient bulk updates
- XOR-based differential update detection
- Packed word storage matching server format
- Lua 5.1 compatible bitwise operations
- Performance statistics tracking

### Changed

#### Performance Improvements
- 30Hz refresh rate throttling (was unlimited)
- Only send updates when LEDs changed (dirty tracking)
- `table.concat()` for efficient string building
- Mathematical indexing instead of hash lookups

#### API Compliance
- 100% monome grid API compatibility
- All device properties: `id`, `cols`, `rows`, `port`, `name`, `serial`
- Static callbacks: `grid.add()`, `grid.remove()`
- Port-based connection: `grid.connect(port)`
- Intensity control: `g:intensity(level)`

#### Code Quality
- Modular architecture with separate class files
- Comprehensive error handling and bounds checking
- Clean separation of mod vs legacy modes
- Consistent coding style

### Fixed
- `string.starts` nil error (replaced with `string.sub`)
- `old_osc_in` nil value error (added null check)
- OSC array sending (now sends as single string)
- Lua 5.1 bitwise operator compatibility

### Deprecated
- Individual LED update messages (`/oscgard/N` with brightness)
- Legacy per-script include method (still works but mod preferred)

---

## [1.0.0] - Original Release

### Added
- Basic TouchOSC grid emulation
- Individual LED updates via OSC
- Key event handling
- TouchOSC layout file (`oscgard.tosc`)
- Arc encoder support (`oscarc.lua`)

### Notes
This is the original implementation by [wangpy](https://github.com/wangpy/toga) (forked from).

---

## Performance Comparison

| Metric | v1.0 (Original) | v2.0 (Current) | Improvement |
|--------|-----------------|----------------|-------------|
| Messages/refresh | 128 | 1 | 128× |
| Bytes/refresh | ~2,560 | ~140 | 94% smaller |
| Memory usage | ~1,024 bytes | 64 bytes | 94% smaller |
| Table objects | ~400 | ~3 | 99% fewer |
| Mod support | No | Yes | New |
| Rotation support | No | Yes | New |
| Multi-client | No | Yes (4) | New |
| API compliance | Partial | 100% | Complete |

---

## Migration Guide

### From v1.0 to v2.0

**For script users:**
1. No changes needed - API is 100% compatible
2. Enable oscgard mod for best experience
3. Optionally update TouchOSC with new bulk processor

**For script developers:**
- All existing oscgard API calls continue to work
- Consider using mod system instead of per-script includes
- New rotation API available: `g:rotation(0-3)`

**For TouchOSC users:**
1. Update `oscgard.tosc` layout
2. Add `touchosc_bulk_processor.lua` for full performance
3. Reconnect after norns restart

---

## Links

- [Original toga by wangpy](https://github.com/wangpy/toga) (forked from)
- [Monome Grid Documentation](https://monome.org/docs/grid/)
- [Norns Grid API Reference](https://monome.org/docs/norns/reference/grid)
- [Lines forum thread](https://llllllll.co/t/oscgard-touchosc-grid-and-arc-controller-for-monome-norns/47902)

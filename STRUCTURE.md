# Network Speed Widget - Project Structure

## Project Overview

A desktop widget plugin for **DankMaterialShell** that monitors real-time network
throughput on a selected interface and graphs it.

### Features

**Real-time monitoring**
- Reads `/proc/net/dev` every second
- Derives per-second throughput from the byte counter delta
- Matches the interface name exactly, so `eth0` does not pick up `veth0`

**Device selection**
- `DankDropdown` in the widget header, populated from `/sys/class/net`
- Rescanned every 10 seconds, rebuilding the list, so interfaces that appear or
  disappear (VPN, dock, tethering) are tracked
- Selection persists to `pluginData.selectedDevice`

**Throughput graphs**
- Rolling 60-sample (60 second) sparkline behind each readout
- Shared vertical scale across both directions
- Gradient area fill plus a brighter trace, in the style of the builtin System
  Monitor desktop widget

**Bitrate unit selection**
- Kbps, Mbps, or Gbps, set in the settings panel
- History is discarded on change, since samples are stored in the display unit

**Desktop widget behaviour**
- Freely movable and resizable, theme-aware via the DMS `Theme` system
- Configurable background opacity

---

## File Structure

```
dank-networt-widget/
├── plugin.json              (Plugin manifest & metadata)
├── NetworkWidget.qml        (Main desktop widget)
├── NetworkSettings.qml      (Settings panel)
├── README.md                (Installation & usage guide)
├── STRUCTURE.md             (This file)
└── idea.md                  (Original requirements)
```

---

## Component Breakdown

### `plugin.json` - Plugin Manifest

- Plugin ID: `networkSpeedWidget`
- Type: `desktop`
- Capabilities: `desktop-widget`
- Component: `./NetworkWidget.qml`, settings: `./NetworkSettings.qml`
- Permissions: `settings_read`, `settings_write`
- Minimum DMS version: 1.2.0
- Icon: `swap_vert`

DMS reads the id from this manifest, not from the installed directory name, so
the folder under `~/.config/DankMaterialShell/plugins/` can be named anything.
Avoid installing two copies under different folder names, though — both would
register the same id.

### `NetworkWidget.qml` - Main Widget Component

**Extends:** `DesktopPluginComponent`

**Settings-backed properties:**
```qml
property string selectedDevice    // Interface name, default "eth0"
property string selectedBitrate   // "Kbps" | "Mbps" | "Gbps", default "Mbps"
property real backgroundOpacity   // 0.0-1.0, from a 0-100 setting
```

**Runtime state:**
```qml
property real downloadSpeed       // Current rx, in the display unit
property real uploadSpeed         // Current tx, in the display unit
property var availableDevices     // Interfaces found under /sys/class/net
property real prevRxBytes         // Previous counter, for the delta
property real prevTxBytes
property var rxHistory            // Up to historySize samples
property var txHistory
readonly property int historySize  // 60 samples == 60s at the 1s poll
readonly property real graphMax   // Peak across both histories; shared scale
```

**Functions:**
- `updateNetworkStats()` - Kicks off the `/proc/net/dev` read
- `loadAvailableDevices()` - Kicks off the `/sys/class/net` scan
- `selectDevice(device)` - Switches interface, resets history, persists the choice
- `pushHistory(history, value)` - Append with a rolling cap at `historySize`
- `resetHistory()` - Clears samples, counters and readouts

**`SpeedGraph` (inline component):** a `Canvas` sparkline taking `series`,
`maxValue`, `traceColor`, `cornerRadius` and `headroom`. It clips to the tile's
rounded rect, plots against a full `historySize` window with a right-edge offset
so the trace scrolls in rather than stretching, and scales peaks to `headroom`
(0.6) of tile height to stay clear of the labels.

**UI Elements:**
1. **Header row:** device `DankDropdown` and the current unit. The dropdown and
   its popup are sized from the widest interface name via `TextMetrics`, and
   `popupWidth` is set so the popup never elides.
2. **Download tile:** `SpeedGraph` over `rxHistory` in `Theme.primary`, a
   gradient scrim to keep labels legible, then icon and readout.
3. **Upload tile:** the same over `txHistory` in `Theme.secondary`.

**Size constraints:**
- Min: 280×180 px

### `NetworkSettings.qml` - Settings Panel

**Extends:** `PluginSettings`

| Setting | Type | Key | Default |
| --- | --- | --- | --- |
| Network Device | `StringSetting` | `selectedDevice` | `eth0` |
| Speed Unit | `SelectionSetting` | `selectedBitrate` | `Mbps` |
| Background Opacity | `SliderSetting` | `backgroundOpacity` | 80 |

`selectedDevice` is the same key the widget's dropdown writes.

---

## Data Flow

```
Every 1 second (Timer):
    statsProcess.running = true
        ↓
    cat /proc/net/dev
        ↓
    SplitParser matches "<selectedDevice>:" exactly
        ↓
    delta = currentBytes - previousBytes
        ↓
    bits = delta × 8, converted to selectedBitrate
        ↓
    downloadSpeed / uploadSpeed updated
        ↓
    appended to rxHistory / txHistory (capped at historySize)
        ↓
    graphMax recomputed, both Canvases repaint

Every 10 seconds (Timer):
    devicesProcess.running = true
        ↓
    ls /sys/class/net, collected into devicesProcess.pending
        ↓
    onExited: availableDevices = sorted pending

User picks a device:
    selectDevice() → resetHistory() → setData("selectedDevice", …)
```

The first sample after load or after a device change reads 0.00, because a delta
needs two counter readings.

---

## Network Speed Calculation

```
Raw Data Source: /proc/net/dev
Format: device: rx_bytes rx_packets rx_errs rx_drop ... tx_bytes tx_packets ...
        (rx_bytes is field 1, tx_bytes is field 9 after the device name)

Every 1000ms:
1. Read current RX/TX bytes for the selected device
2. delta = currentBytes - previousBytes, floored at 0
3. bits = delta × 8
4. Convert to the selected unit:
   - Kbps: bits / 1,000
   - Mbps: bits / 1,000,000
   - Gbps: bits / 1,000,000,000
5. Display with 2 decimal places
```

---

## Installation & Development

```bash
# Symlink for development
ln -sfn "$PWD" ~/.config/DankMaterialShell/plugins/networkSpeedWidget

dms ipc call plugins enable networkSpeedWidget
dms ipc call plugins reload networkSpeedWidget
```

Then add an instance via DMS Settings → Desktop Widgets; enabling the plugin
alone does not place one. Check with `dms ipc call desktopWidget list`.

There is no `qmllint` in the DMS install, so the practical compile check is to
reload and watch the journal:

```bash
journalctl --user -f | grep -i qml
```

A broken widget logs `PluginService ... component error` naming the file. Silence
after a reload means it compiled.

---

## QML Features Used

- `DesktopPluginComponent` - Base desktop widget
- `pluginData` / `setData()` - Auto-synced settings
- `Process` + `SplitParser` (`Quickshell.Io`) - Shell command output
- `Timer` - Periodic polling and device rescan
- `Canvas` - Sparkline rendering
- `TextMetrics` - Sizing the dropdown to the widest name
- Inline components (`component SpeedGraph: Canvas`)
- `Theme.*` - DMS theme integration
- `DankDropdown`, `DankIcon`, `StyledText` - Shell widgets from `qs.Widgets`

---

## Security & Permissions

- Reads only `/proc/net/dev` and `/sys/class/net`
- No elevated privileges required
- Persistence goes through `PluginService`

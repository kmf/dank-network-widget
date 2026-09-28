# Network Speed Widget for DankMaterialShell

A desktop widget for DankMaterialShell that monitors real-time network throughput,
with an interface picker and rolling throughput graphs.

## Features

- 📊 **Real-time Network Monitoring** - Updates every second with current upload/download speeds
- 📈 **Throughput Graphs** - Rolling 60-second sparkline behind each of the download and upload readouts
- 🖥️ **Device Dropdown** - Pick the interface to monitor directly on the widget; the list is rescanned every 10 seconds so VPN, dock and tethering interfaces appear without a restart
- ⚡ **Bitrate Units** - Display speeds in Kbps, Mbps, or Gbps
- 🎨 **Transparent Design** - Configurable background opacity to see your wallpaper
- 🎯 **Desktop Widget** - Freely positionable and resizable on your desktop

## Installation

### Quick Setup

1. **Install the plugin** into the DankMaterialShell plugins directory. DMS takes
   the plugin id from `plugin.json`, not from the folder name, so the directory
   can be called anything — but do not leave two copies of the plugin installed
   under different folder names, since both register the same id.

   ```bash
   mkdir -p ~/.config/DankMaterialShell/plugins
   cp -r dank-networt-widget ~/.config/DankMaterialShell/plugins/networkSpeedWidget
   ```

   Or symlink it for development, so edits are picked up by a reload:

   ```bash
   ln -sfn "$PWD" ~/.config/DankMaterialShell/plugins/networkSpeedWidget
   ```

2. **Enable it** in DMS:

   ```bash
   dms ipc call plugins enable networkSpeedWidget
   dms ipc call plugins reload networkSpeedWidget
   dms ipc call plugins status networkSpeedWidget   # -> loaded
   ```

   Or via DankMaterialShell Settings → Plugins.

3. **Add it to the desktop** via DMS Settings → Desktop Widgets. Enabling the
   plugin only makes it available; it does not place an instance on the desktop.
   Confirm placement with:

   ```bash
   dms ipc call desktopWidget list
   ```

### Configuration

The **network device** is chosen on the widget itself, from the dropdown in the
header. The selection is persisted to `pluginData.selectedDevice`.

The remaining settings live in DMS Settings → Plugins → Network Speed Widget:

- **Speed Unit** - Kbps, Mbps, or Gbps
- **Background Opacity** - 0-100%

The settings panel also exposes a **Network Device** text field, which writes the
same key as the dropdown. The dropdown is the easier path; the field is useful for
an interface that is not currently up.

## Usage

### Finding Your Network Interface

The dropdown lists everything under `/sys/class/net`. To see the same list:

```bash
ls /sys/class/net
```

Common interfaces:
- `enp*` / `eth0` - Wired Ethernet
- `wlp*` / `wlan0` - WiFi
- `tailscale0`, `wg0` - VPN tunnels
- `lo` - Loopback (usually not useful to monitor)

### Reading the Graphs

Each tile draws the last 60 samples (one per second) for that direction.

- Both graphs share one vertical scale, so the download and upload traces are
  directly comparable rather than each self-scaling.
- History is cleared when you change device or unit, since samples are stored in
  the displayed unit.
- The trace scrolls in from the right as history fills, rather than stretching.

### Live Reloading (Development)

```bash
dms ipc call plugins reload networkSpeedWidget
```

QML errors show up in the journal:

```bash
journalctl --user -f | grep -i qml
```

A failure to compile the widget appears as a `PluginService ... component error` line.

## How It Works

The widget reads network statistics from `/proc/net/dev` every second:

1. Read current RX/TX byte counters for the selected interface
2. Subtract the previous sample to get bytes transferred in that second
3. Convert bytes to bits (× 8), then to the selected unit
4. Update the readouts and append to the 60-sample history

Interface discovery runs `ls /sys/class/net` on startup and every 10 seconds,
rebuilding the list each time so interfaces that go away drop out.

## File Structure

```
dank-networt-widget/
├── plugin.json           # Plugin manifest
├── NetworkWidget.qml     # Main desktop widget component
├── NetworkSettings.qml   # Settings panel
├── README.md             # This file
├── STRUCTURE.md          # Technical detail
└── idea.md               # Original requirements
```

## Requirements

- DankMaterialShell >= 1.2.0
- Linux system (uses `/proc/net/dev` and `/sys/class/net`)
- Wayland compositor (niri, hyprland, etc.)

## Permissions

The plugin requires:
- `settings_read` - To load saved preferences
- `settings_write` - To save configuration changes

## Troubleshooting

**Widget doesn't show:**
- `dms ipc call plugins status networkSpeedWidget` should report `loaded`
- `dms ipc call desktopWidget list` should list a `networkSpeedWidget` instance;
  if not, add one via DMS Settings → Desktop Widgets
- Check the journal for a `component error` line naming `NetworkWidget.qml`

**Speeds stay at 0.00:**
- The interface name must match `/proc/net/dev` exactly. Pick it from the
  dropdown rather than typing it.
- A newly selected device shows 0.00 for one second while the first delta is
  established.

**Device dropdown is empty:**
- Check that `ls /sys/class/net` returns something
- The list populates on the first scan after load, and every 10 seconds after

**Long interface names are cut off:**
- The dropdown popup always shows names in full. The trigger elides only when
  the widget itself is too narrow — widen the widget to fit.

## Development

### Editor Setup (VSCode)

1. Install the QML Extension
2. Clone DankMaterialShell repo with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/AvengeMedia/DankMaterialShell.git
   cd DankMaterialShell/quickshell
   touch .qmlls.ini
   qs -p .  # Press Ctrl+C after language server starts
   ```
3. Open this directory in VSCode for QML autocomplete

### Plugin API Reference

- [`DesktopPluginComponent`](https://danklinux.com/docs/1.6/dankmaterialshell/plugin-development#desktop-plugins) - Base component for desktop widgets
- [`pluginData`](https://danklinux.com/docs/1.6/dankmaterialshell/plugin-development#plugin-settings) - Auto-synced settings object
- [`pluginService`](https://danklinux.com/docs/1.6/dankmaterialshell/plugin-development#plugin-settings) - Service for saving/loading data

Widget components used from the shell (`qs.Widgets`): `DankDropdown`, `DankIcon`,
`StyledText`. Their sources are readable at
`/usr/share/quickshell/dms/quickshell/Widgets/`.

## License

Freely available for use with DankMaterialShell.

## Related Resources

- [DankMaterialShell Documentation](https://danklinux.com)
- [Plugin Development Guide](https://danklinux.com/docs/1.6/dankmaterialshell/plugin-development)
- [Plugin Registry](https://github.com/avengemedia/dms-plugin-registry)

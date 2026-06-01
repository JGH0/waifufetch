# JSON Config File

waifufetch supports a JSON config file for full control over the system
info display. The config is loaded from one of these locations:

- `~/.config/waifufetch/config.json`
- `$XDG_CONFIG_HOME/waifufetch/config.json`
- Custom path via `--config <path>` or `-c <path>`

## Quick Example

```json
{
  "logo": {
    "padding": {
      "top": 2
    }
  },
  "display": {
    "separator": " => "
  },
  "modules": [
    { "type": "os", "key": "OS ", "keyColor": "bold 31" },
    { "type": "host", "key": "Host ", "keyColor": "cyan" },
    "break",
    { "type": "kernel", "key": "Kernel ", "keyColor": "32" },
    { "type": "uptime", "key": "Uptime ", "keyColor": "green" },
    { "type": "shell", "key": "Shell ", "keyColor": "magenta" },
    { "type": "terminal", "key": "Term ", "keyColor": "yellow" },
    "break",
    { "type": "packages", "key": "Pkgs ", "keyColor": "bold 33" },
    { "type": "memory", "key": "RAM ", "keyColor": "36" },
    { "type": "disk", "key": "Disk ", "keyColor": "35" }
  ]
}
```

## Fields

### `logo.padding.top`

Number of blank lines above the output. Default: 0

```json
{ "logo": { "padding": { "top": 2 } } }
```

### `display.separator`

String between the key label and the value. Default: `": "`

```json
{ "display": { "separator": " = " } }
```

```json
{ "display": { "separator": " => " } }
```

### `modules`

Array of items to display. If omitted, all available info is shown
in default format (cyan key, colon separator).

Each item is either:

- **A string** `"break"` — inserts a blank line
- **An object** with the following fields:

| Field | Required | Description |
|---|---|---|
| `type` | yes | Info type name (case-insensitive, see list below) |
| `key` | no | Label text shown before the value. Omit to show the value alone. |
| `keyColor` | no | Color for the key label (see color values below) |
| `format` | no | Not yet implemented (reserved for future use) |

## Color Values

For `keyColor`, use one of:

| Format | Examples |
|---|---|
| ANSI number | `31`, `32`, `33`, `34`, `35`, `36`, `37` |
| Color name | `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white` |
| Bold prefix | `"bold 31"`, `"bold cyan"`, `"bold green"` |

Color code reference:

| Code | Name | Description |
|---|---|---|
| 30 | black | Black |
| 31 | red | Red |
| 32 | green | Green |
| 33 | yellow | Yellow |
| 34 | blue | Blue |
| 35 | magenta | Magenta |
| 36 | cyan | Cyan |
| 37 | white | White |

## Available Info Types

| Type name | Shows | Example |
|---|---|---|
| `os` | Operating system | Arch Linux, macOS |
| `host` | User@hostname | jgh@archa |
| `kernel` | Kernel version | 6.10.0-zen1 |
| `uptime` | System uptime | 2h 15m |
| `uptime_unix` | Boot timestamp (Unix epoch) | 1780328855 |
| `shell` | Current shell | fish, bash, zsh |
| `terminal` | Terminal emulator | kitty, xterm-kitty |
| `wm` or `de` | Window manager / DE | sway, hyprland |
| `wmtheme` | WM/GTK theme | Adwaita |
| `icons` | Icon theme | Papirus-Dark |
| `cursor` | Cursor theme | Bibata-Modern-Ice |
| `terminalfont` | Terminal font name | FiraCode Nerd Font |
| `cpu` | CPU model | 11th Gen Intel Core i7-1165G7 |
| `gpu` | GPU model | Intel TigerLake-LP GT2 |
| `memory` | RAM usage | 6.0Gi/15Gi |
| `swap` | Swap usage | 0B/4.0Gi |
| `disk` | Disk usage (used/total) | 373G/468G (85%) |
| `disk_total` | Total disk size | 468G |
| `packages` | Installed package count | 2401 |
| `resolution` | Display resolution | 1920x1080 |
| `monitor` | Number of monitors | 2 |
| `localip` | Local IP address | 192.168.1.157 |
| `publicip` | Public IP address | 178.82.194.181 |
| `battery` | Battery level | 100% (Full/Charging) |
| `locale` | System locale | en_US.UTF-8 |
| `init` | Init system | systemd |
| `date` | Current date and time | 2026-06-01 19:21 |
| `song` | Currently playing media | Song Title - Artist |

## More Examples

### Minimal config — just padding

```json
{
  "logo": {
    "padding": { "top": 1 }
  }
}
```

### Custom colors and separator

```json
{
  "display": {
    "separator": " -> "
  },
  "modules": [
    { "type": "os", "key": "OS", "keyColor": "bold red" },
    { "type": "kernel", "key": "Kernel", "keyColor": "bold green" },
    "break",
    { "type": "cpu", "key": "CPU", "keyColor": "bold yellow" },
    { "type": "gpu", "key": "GPU", "keyColor": "bold blue" },
    "break",
    { "type": "memory", "key": "RAM", "keyColor": "bold magenta" },
    { "type": "disk", "key": "Disk", "keyColor": "bold cyan" }
  ]
}
```

### Show only a few items

```json
{
  "modules": [
    { "type": "os", "key": "OS: " },
    { "type": "host", "key": "Box: " },
    { "type": "uptime", "key": "Up: " },
    "break",
    { "type": "packages", "key": "Pkgs: " },
    { "type": "date", "key": "Date: " }
  ]
}
```

### No key labels (value only)

```json
{
  "modules": [
    { "type": "os" },
    { "type": "host" },
    "break",
    { "type": "kernel" },
    { "type": "uptime" }
  ]
}
```

## Usage

```bash
# Use default config path
waifufetch

# Use custom config
waifufetch --config /path/to/config.json
waifufetch -c /path/to/config.json
```

The config file is only used by `waifufetch` (system info display).
For `waifu` (standalone image display), the config file has no effect.

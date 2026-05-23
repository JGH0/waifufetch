# waifufetch

**System info with a random waifu decoration.** Like fastfetch/neofetch, but
with a waifu image as the ASCII art logo instead of a distro logo.

Uses **nekosapi.com v4**, **waifu.im**, and **nekos.best** APIs.

## Requirements

- **curl** — API requests
- **jq** — JSON parsing

### Optional (for waifu display)

Auto-detected in order of preference:

- **kitty** terminal — native image display via `kitty +kitten icat`
- **chafa** — terminal image display, supports sixel/kitty/iterm2 protocols
- **img2txt** (from caca-utils) — colored ASCII art
- **jp2a** — black & white ASCII art

## Installation

### Arch Linux (AUR)

```bash
yay -S waifufetch
# or
paru -S waifufetch
```

### Manual

```bash
sudo install -m755 waifufetch /usr/local/bin/waifufetch
sudo install -m755 waifu /usr/local/bin/waifu
```

## Usage

```
Usage: waifufetch [rating]

Display system info with a random waifu decoration.

Ratings (optional):
  safe        safe only (default)
  suggestive  exact: suggestive only
  borderline  exact: borderline only
  explicit    exact: explicit only

Use waifufetch --setDefaultSFW <rating> to change the default.

APIs: nekosapi.com v4, waifu.im
Install chafa, img2txt, or jp2a for waifu ASCII art.
```

### Examples

```bash
waifufetch              # system info + safe waifu
waifufetch suggestive   # system info + suggestive waifu only
waifufetch --setDefaultSFW borderline  # include up to borderline
```

### Companion: `waifu`

The `waifu` command is also included — fetch and display standalone waifu
images (not as fetch decoration). See `waifu --help`.

```
Usage: waifu [category|rating] [tag] [--debug]

  waifu                      - default SFW
  waifu sfw [tag]            - SFW (default rating, cascading)
  waifu nsfw [tag]           - NSFW (borderline + explicit)
  waifu safe [tag]           - exact: safe only
  waifu suggestive [tag]     - exact: suggestive only
  waifu borderline [tag]     - exact: borderline only
  waifu explicit [tag]       - exact: explicit only
  waifu --setDefaultSFW <r>  - set default SFW rating
  waifu --debug              - show detailed debug info
  waifu nsfw --help          - show NSFW-specific help
```

## Configuration

Default SFW rating is stored in `/tmp/waifu/default_sfw` and persists until
reboot.

## License

MIT

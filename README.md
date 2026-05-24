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
Usage: waifufetch [displayer] [rating] [tag] [--noLink] [--debug]

Display system info with a random waifu decoration.

  waifufetch                      - default SFW (safe)
  waifufetch sfw [tag]            - SFW (default rating, cascading)
  waifufetch nsfw [tag]           - NSFW (borderline + explicit)
  waifufetch safe [tag]           - exact: safe only
  waifufetch suggestive [tag]     - exact: suggestive only
  waifufetch borderline [tag]     - exact: borderline only
  waifufetch explicit [tag]       - exact: explicit only

  waifufetch icat                 - force kitty icat image display
  waifufetch chafa suggestive     - force chafa with suggestive rating

  waifufetch --setDefaultSFW <r>       - set default SFW rating
  waifufetch --setDefaultDisplayer <d> - set default image displayer
  waifufetch --noLink                  - suppress image URL output
  waifufetch --debug                   - show detailed debug info
  waifufetch --help                    - show this help

Ratings: safe, suggestive, borderline, explicit
Displayers: icat, chafa, img2txt, jp2a

Categories: waifu neko kitsune husbando maid uniform selfies
Characters: raiden-shogun mori-calliope rem ...

APIs: nekosapi.com v4, waifu.im, nekos.best
Note: Tags and ratings depend on API metadata and are not 100% precise.
      You may occasionally see unexpected content.
      Install chafa, img2txt, or jp2a for waifu ASCII art.
```

### Examples

```bash
waifufetch              # system info + safe waifu
waifufetch suggestive   # system info + suggestive waifu only
waifufetch chafa        # use chafa as displayer
waifufetch icat suggestive neko  # icat display with suggestive rating
waifufetch --setDefaultSFW borderline  # include up to borderline
waifufetch --setDefaultDisplayer chafa  # use chafa by default
```

### Companion: `waifu`

The `waifu` command is also included -- fetch and display standalone waifu
images (not as fetch decoration). See `waifu --help`.

```
Usage: waifu [displayer] [category|rating] [tag] [--debug]

  waifu                      - default SFW
  waifu sfw [tag]            - SFW (default rating, cascading)
  waifu nsfw [tag]           - NSFW (borderline + explicit)
  waifu safe [tag]           - exact: safe only
  waifu suggestive [tag]     - exact: suggestive only
  waifu borderline [tag]     - exact: borderline only
  waifu explicit [tag]       - exact: explicit only

  waifu icat                 - force kitty icat display
  waifu chafa suggestive     - force chafa with rating

  waifu --setDefaultSFW <r>       - set default SFW rating
  waifu --setDefaultDisplayer <d> - set default image displayer
  waifu --debug                   - show detailed debug info
  waifu nsfw --help               - show NSFW-specific help
```

## Configuration

Config files are stored in `~/.config/waifu/`:

- `default_sfw` -- stored default SFW rating (safe, suggestive, or borderline)
- `default_displayer` -- stored default displayer (icat, chafa, img2txt, or jp2a)

Set with `waifufetch --setDefaultSFW <rating>` or
`waifufetch --setDefaultDisplayer <displayer>`.

## License

MIT

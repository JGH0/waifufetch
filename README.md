# waifufetch

**System info with a random waifu decoration.** Like fastfetch/neofetch, but
with a waifu image as the ASCII art logo instead of a distro logo.

Uses **nekosapi.com v4**, **waifu.im**, and **nekos.best** APIs.

Something not working? [Open an issue](https://github.com/JGH0/waifufetch/issues).

## Requirements

- **curl** — API requests
- **jq** — JSON parsing

### Optional (for waifu display)

Auto-detected in order of preference:

- **kitty** terminal — native image display via `kitty +kitten icat`
- **chafa** — terminal image display, supports sixel/kitty/iterm2 protocols
- **img2txt** (from caca-utils) — colored ASCII art
- **jp2a** — black & white ASCII art

### GIF Animation Support

- **chafa** (recommended) — full animated GIF support in-terminal
- **kitty icat** — animated GIF support via icat
- **img2txt** / **jp2a** — GIFs are displayed as static frames (no animation)

When using `-i <file>` with an animated GIF, chafa or icat will show the full
animation. jp2a and img2txt only show a single frame (a warning is printed).

## Installation

### Arch Linux (AUR)

```bash
yay -S waifufetch
# or
paru -S waifufetch
```


### Manual Install

#### 1. Clone repository

```bash
git clone https://github.com/JGH0/waifufetch.git
cd waifufetch
```

#### 3. Install dependencies

```bash
# use your prefered package manager
sudo pacman -S curl jq chafa
```

#### 4. Install commands

```bash
sudo install -m755 libwaifu.sh /usr/local/bin/libwaifu.sh
sudo install -m755 waifu /usr/local/bin/waifu
sudo install -m755 waifufetch /usr/local/bin/waifufetch
```

#### If `install` is unavailable:

```bash
sudo cp libwaifu.sh /usr/local/bin/
sudo cp waifu /usr/local/bin/
sudo cp waifufetch /usr/local/bin/
sudo chmod +x /usr/local/bin/libwaifu.sh /usr/local/bin/waifu /usr/local/bin/waifufetch
```

`libwaifu.sh` is sourced by both commands and must be in the same directory.

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

  waifufetch --setDefaultSFW <r>          - set default SFW rating
                                       ("" to reset to safe)
  waifufetch --setDefaultDisplayer <d>    - set default image displayer
                                       ("" to clear, auto-detect)
  waifufetch --resetSettings              - remove all saved config files
  waifufetch -i <file>                    - display a local image/GIF file with system info
  waifufetch --noLink                     - suppress image URL output
  waifufetch --debug                      - show detailed debug info
  waifufetch --help                       - show this help
  waifufetch -v, --version                - show version and exit

Ratings: safe, suggestive, borderline, explicit
Displayers: icat, chafa, img2txt, jp2a

Categories: waifu neko kitsune husbando maid uniform selfies
Characters: raiden-shogun mori-calliope rem marin-kitagawa ...

APIs: nekosapi.com v4, waifu.im, nekos.best
Note: Tags and ratings depend on API metadata and are not 100% precise.
      Returned images are verified to match the requested category tag.
      Install chafa for GIF animation support.

Something not working? Report it at:
<https://github.com/JGH0/waifufetch/issues>
```

### Examples

```bash
waifufetch              # system info + safe waifu
waifufetch suggestive   # system info + suggestive waifu only
waifufetch chafa        # use chafa as displayer
waifufetch icat suggestive neko  # icat display with suggestive rating
waifufetch --setDefaultSFW borderline  # include up to borderline
waifufetch --setDefaultDisplayer chafa  # use chafa by default
waifufetch --setDefaultDisplayer ""   # back to auto-detect
waifufetch --resetSettings             # remove all config files
waifufetch -i ~/Pictures/waifu.gif  # display a local file with system info
```
<img width="887" height="428" alt="image" src="https://github.com/user-attachments/assets/f07a4e5d-f312-43e7-a048-501ec5ac18b3" />

<img width="auto" height="500" alt="image" src="https://github.com/user-attachments/assets/038193f0-eb9f-40b2-841a-59729b4934e4" />

<img width="auto" height="500" alt="image" src="https://github.com/user-attachments/assets/d3a9a97d-65e1-45d1-8507-f9e092645dd1" />


### Companion: `waifu`

Both `waifu` and `waifufetch` share the same codebase via `libwaifu.sh`.
They use the same API fetching, caching, and display logic. The only
difference is output format — `waifu` shows the image full-screen, while
`waifufetch` shows it side-by-side with system info.

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

  waifu -i <file>                    - display a local image/GIF file
  waifu --setDefaultSFW <r>          - set default SFW rating ("" to reset)
  waifu --setDefaultDisplayer <d>    - set default image displayer ("" to clear)
  waifu --resetSettings              - remove all saved config files
  waifu --noLink                     - suppress image URL output
  waifu --debug                      - show detailed debug info
  waifu -v, --version                - show version and exit
  waifu nsfw --help                  - show NSFW-specific help
```

## Configuration

Config files are stored in `~/.config/waifu/`:

- `default_sfw` -- stored default SFW rating (safe, suggestive, or borderline)
- `default_displayer` -- stored default displayer (icat, chafa, img2txt, or jp2a)

Set with `waifufetch --setDefaultSFW <rating>` or
`waifufetch --setDefaultDisplayer <displayer>`.

Reset all settings: `waifufetch --resetSettings`.

## License

MIT

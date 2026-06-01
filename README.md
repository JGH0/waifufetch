# waifufetch

**System info with a random waifu decoration.** Like fastfetch/neofetch, but
with a waifu image as the ASCII art logo instead of a distro logo.

Uses **nekosapi.com v4**, **waifu.im**, **nekos.best**, and **danbooru.donmai.us**
APIs. No API keys required.

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

#### 2. Install dependencies

```bash
# use your preferred package manager
sudo pacman -S curl jq chafa
```

#### 3. Install commands

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

```bash
waifufetch [displayer] [rating] [tag] [--noLink] [--debug]

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
  waifufetch --setDefaultAPI <source>     - set default API source
                                       (auto, waifu.im, nekosapi, nekos.best, danbooru)
  waifufetch --resetSettings              - remove all saved config files
  waifufetch -i <file>                    - display a local image/GIF with system info

  waifufetch --list-tags                  - list all SFW tags
  waifufetch nsfw --list-tags             - list ALL tags (SFW + NSFW + Danbooru)
  waifufetch --list-categories            - list categories only
  waifufetch --list-ratings               - list rating levels

  waifufetch --noLink                     - suppress image URL output
  waifufetch --debug                      - show detailed debug info
  waifufetch --config <file>              - load JSON config (see CONFIG.md)
  waifufetch -c <file>                    - same as --config
  waifufetch --help                       - show this help
  waifufetch -v, --version                - show version and exit
```

### Companion: `waifu`

Both `waifu` and `waifufetch` share the same codebase via `libwaifu.sh`.
They use the same API fetching, caching, and display logic. The only
difference is output format — `waifu` shows the image full-screen, while
`waifufetch` shows it side-by-side with system info.

The `waifu` command is also included — fetch and display standalone waifu
images (not as neofetch decoration). See `waifu --help`.

```bash
waifu [displayer] [category|rating] [tag] [--debug]
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
  waifu -a, --api <source>           - use a specific API for this request
  waifu --setDefaultSFW <r>          - set default SFW rating ("" to reset)
  waifu --setDefaultDisplayer <d>    - set default displayer ("" to clear)
  waifu --setDefaultAPI <source>     - set default API source
  waifu --resetSettings              - remove all saved config files
  waifu --list-tags                  - list all SFW tags
  waifu nsfw --list-tags             - list ALL tags (SFW + NSFW + Danbooru)
  waifu --noLink                     - suppress image URL output
  waifu --debug                      - show detailed debug info
  waifu -v, --version                - show version and exit
  waifu nsfw --help                  - show NSFW-specific help
```

## API Sources

The program uses four APIs in a fallback chain. No API keys required:

| Source | Auth | Content | Tags |
|---|---|---|---|
| **nekosapi.com v4** | None | SFW + NSFW anime | waifu, neko, and others |
| **waifu.im** | None | SFW + NSFW anime | maid, uniform, selfies, ero, ecchi, hentai, characters |
| **nekos.best** | None | SFW anime + reaction GIFs | waifu, neko, kitsune, husbando, 50+ GIFs |
| **danbooru.donmai.us** | None (rate-limited IP) | SFW + NSFW, any rating | 1M+ tags including femboy, trap, cosplay, characters |

Fallback chain: `nekosapi -> waifu.im -> nekos.best -> danbooru`

Danbooru-only tags (femboy, trap, catgirl, bikini, etc.) route directly to
Danbooru, skipping the other APIs.

Select a specific API:
```bash
waifu -a danbooru femboy
waifufetch -a nekosapi suggestive neko
```

Set a persistent default:
```bash
waifu --setDefaultAPI danbooru
waifu --setDefaultAPI auto   # back to fallback chain
```

## Tags

```
SFW Tags:    waifu, neko, kitsune, husbando, maid, uniform, selfies
NSFW Tags:   ero, ecchi, hentai, oppai, ass, milf, oral, paizuri
Danbooru:    femboy, trap, catgirl, original, cosplay, bikini, swimsuit,
             lingerie, pantyhose, stockings, bunny_girl, blush, skirt, thighhighs
Characters:  raiden-shogun, mori-calliope, rem, marin-kitagawa,
             genshin-impact, kamisato-ayaka
GIFs:        lurk, shoot, sleep, clap, shrug, stare, wave, poke, confused,
             smile, peck, wink, sip, blush, smug, tickle, yeet, think,
             highfive, feed, wag, bite, teehee, shocked, bleh, bored, nom,
             nya, yawn, facepalm, cuddle, kick, happy, carry, hug, kabedon,
             baka, bonk, pat, angry, spin, shake, run, nod, nope, kiss,
             dance, punch, handshake, slap, cry, lappillow, pout, blowkiss,
             handhold, salute, thumbsup, laugh, tableflip
```

Run `waifu --list-tags` for all SFW tags or `waifu nsfw --list-tags` for all.

## Ratings

```
safe          - safe only
suggestive    - safe + suggestive
borderline    - safe + suggestive + borderline
explicit      - explicit only (via nsfw mode)
nsfw          - borderline + explicit
```

Ratings cascade: `borderline` includes safe, suggestive, and borderline
content. `nsfw` mode uses borderline + explicit.

Set default SFW level:
```bash
waifufetch --setDefaultSFW borderline
```

## JSON Config

waifufetch supports a JSON config file for full control over the system
info display. See [CONFIG.md](CONFIG.md) for complete documentation.

```bash
# Use default path (~/.config/waifufetch/config.json)
waifufetch

# Custom config
waifufetch --config my-config.json
waifufetch -c my-config.json
```

```json
{
  "logo": {
    "padding": { "top": 0 }
  },
  "display": {
    "separator": " => "
  },
  "modules": [
    { "type": "os", "key": "OS ", "keyColor": "bold 31" },
    { "type": "host", "key": "Host ", "keyColor": "cyan" },
    "break",
    { "type": "kernel", "key": "Kernel ", "keyColor": "32" },
    { "type": "packages", "key": "Pkgs ", "keyColor": "bold 33" }
  ]
}
```

## Examples

```bash
waifufetch                        # system info + safe waifu
waifufetch suggestive             # system info + suggestive waifu
waifufetch chafa                  # use chafa as displayer
waifufetch icat suggestive neko   # icat + suggestive + neko tag
waifu                             # fetch and display a random waifu
waifu nsfw                        # fetch a NSFW waifu
waifu -a danbooru femboy          # fetch a femboy via Danbooru
waifu explicit trap               # fetch explicit trap content
waifu --setDefaultSFW borderline  # include up to borderline
waifu --setDefaultAPI danbooru    # use Danbooru by default
waifu --resetSettings             # remove all config files
waifu -i ~/Pictures/waifu.gif     # display a local file
waifu --list-tags                 # show all SFW tags
waifu nsfw --list-tags            # show ALL tags (SFW + NSFW)
```

## Screenshots

<img width="887" height="428" alt="waifufetch output" src="https://github.com/user-attachments/assets/f07a4e5d-f312-43e7-a048-501ec5ac18b3" />

<img width="auto" height="500" alt="waifu display" src="https://github.com/user-attachments/assets/038193f0-eb9f-40b2-841a-59729b4934e4" />

<img width="auto" height="500" alt="waifu femboy" src="https://github.com/user-attachments/assets/d3a9a97d-65e1-45d1-8507-f9e092645dd1" />

## License

MIT

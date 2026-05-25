#!/usr/bin/env bash
# libwaifu.sh - Shared library for waifu and waifufetch
# Sourced by both scripts
set -euo pipefail

# ============================================================
# Version
# ============================================================
VERSION="1.2.1"

# ============================================================
# Tag lists (not 100% precise - the APIs decide what fits)
# ============================================================
WIM_SFW=(waifu maid uniform selfies)
WIM_NSFW=(ero ecchi hentai oppai ass milf oral paizuri)
WIM_CHARS=(raiden-shogun mori-calliope rem marin-kitagawa genshin-impact kamisato-ayaka)
NB_STATIC=(waifu neko kitsune husbando)
NB_GIFS=(lurk shoot sleep clap shrug stare wave poke confused smile \
         peck wink sip blush smug tickle yeet think highfive feed wag bite \
         teehee shocked bleh bored nom nya yawn facepalm cuddle kick happy \
         carry hug kabedon baka bonk pat angry spin shake run nod nope kiss \
         dance punch handshake slap cry lappillow pout blowkiss handhold \
         salute thumbsup laugh tableflip)
KNOWN_RATINGS=(safe suggestive borderline explicit sfw nsfw)
ALL_RATINGS=(safe suggestive borderline explicit sfw nsfw)
ALL_KNOWN_TAGS=("${WIM_SFW[@]}" "${WIM_NSFW[@]}" "${WIM_CHARS[@]}" "${NB_STATIC[@]}" "${NB_GIFS[@]}")

# ============================================================
# Config: default SFW rating
# ============================================================
WAIFU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waifu"
CONFIG_FILE="$WAIFU_CONFIG_DIR/default_sfw"
DEFAULT_SFW="safe"

if [[ -f "$CONFIG_FILE" ]]; then
    read -r READ_VAL < "$CONFIG_FILE" || true
    READ_VAL="$(printf '%s' "$READ_VAL" | xargs)"  # trim
    case "$READ_VAL" in
        safe|suggestive|borderline) DEFAULT_SFW="$READ_VAL" ;;
    esac
fi

# ============================================================
# Displayer config
# ============================================================
WAIFU_DISPLAYER_FILE="$WAIFU_CONFIG_DIR/default_displayer"
DEFAULT_DISPLAYER=""

if [[ -f "$WAIFU_DISPLAYER_FILE" ]]; then
    read -r DISPLAYER_VAL < "$WAIFU_DISPLAYER_FILE" || true
    DISPLAYER_VAL="$(printf '%s' "$DISPLAYER_VAL" | xargs)"
    case "$DISPLAYER_VAL" in
        icat|chafa|img2txt|jp2a) DEFAULT_DISPLAYER="$DISPLAYER_VAL" ;;
    esac
fi

# ============================================================
# is_gif_file - check if a file is an animated GIF
# ============================================================
is_gif_file() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    [[ "${f,,}" == *.gif ]] && return 0
    local magic
    magic=$(dd if="$f" bs=1 count=3 2>/dev/null)
    [[ "$magic" == "GIF" ]] && return 0
    return 1
}

# ============================================================
# build_api_rating - compute API_RATING from MODE, IS_DIRECT_RATING, RATING_LEVEL
# ============================================================
build_api_rating() {
    API_RATING=""
    if [[ "$MODE" == "nsfw" && $IS_DIRECT_RATING -eq 0 ]]; then
        API_RATING="borderline,explicit"
    elif [[ $IS_DIRECT_RATING -eq 1 ]]; then
        API_RATING="$RATING_LEVEL"
    else
        case "$RATING_LEVEL" in
            safe)       API_RATING="safe" ;;
            suggestive) API_RATING="safe,suggestive" ;;
            borderline) API_RATING="safe,suggestive,borderline" ;;
            explicit)   API_RATING="safe,suggestive,borderline,explicit" ;;
        esac
    fi
}

# ============================================================
# setup_cache - set cache variables
# ============================================================
setup_cache() {
    CAN_CACHE=0
    CACHE_DIR="/tmp/waifu"
    if mkdir -p "$CACHE_DIR" 2>/dev/null && [[ -w "$CACHE_DIR" ]]; then
        CAN_CACHE=1
    fi
    CACHE_KEY="${MODE}|${IS_DIRECT_RATING}|${RATING_LEVEL}|${CATEGORY}"
    CM="$CACHE_DIR/meta.txt"
    CF="$CACHE_DIR/img"
}

# ============================================================
# check_cache - read cache, set IMAGE_URL/IMAGE_FILE if hit
# ============================================================
check_cache() {
    IMAGE_URL=""
    IMAGE_FILE=""
    FROM_CACHE=0

    if [[ $CAN_CACHE -eq 1 && -f "$CM" && -f "$CF" ]]; then
        read -r CK < "$CM" || true
        CU="$(tail -1 "$CM" 2>/dev/null || true)"
        if [[ "$CK" == "$CACHE_KEY" && -n "$CU" ]]; then
            IMAGE_URL="$CU"
            IMAGE_FILE="$CF"
            FROM_CACHE=1
            [[ $DEBUG -eq 1 ]] && echo "[debug] cache HIT: $CACHE_KEY" >&2
        else
            rm -f "$CM" "$CF"
            [[ $DEBUG -eq 1 ]] && echo "[debug] cache MISS: wanted '$CACHE_KEY', had '$CK'" >&2
        fi
    else
        [[ $DEBUG -eq 1 ]] && echo "[debug] cache MISS: no cache files" >&2
    fi
}

# ============================================================
# save_cache - write current image to cache
# ============================================================
save_cache() {
    if [[ $CAN_CACHE -eq 1 ]]; then
        printf '%s\n%s\n' "$CACHE_KEY" "$IMAGE_URL" > "$CM" 2>/dev/null
        cp "$IMAGE_FILE" "$CF" 2>/dev/null
    fi
}

# ============================================================
# invalidate_cache - clear cache files
# ============================================================
invalidate_cache() {
    if [[ $CAN_CACHE -eq 1 ]]; then
        rm -f "$CM" "$CF"
    fi
}

# ============================================================
# fetch_and_cache - get an image (cache then API with fallback)
# Sets IMAGE_FILE and IMAGE_URL on success, clears them on failure.
# Assumes MODE, IS_DIRECT_RATING, RATING_LEVEL, CATEGORY are set.
# ============================================================
fetch_and_cache() {
    setup_cache
    # Check cache first (instant)
    check_cache
    if [[ -n "$IMAGE_URL" && -n "$IMAGE_FILE" && -s "$IMAGE_FILE" ]]; then
        return 0
    fi
    # Cache miss -- fetch from API
    local tmpfile url
    tmpfile="$(mktemp /tmp/waifu-fetch-XXXXXX 2>/dev/null)"
    url="$(fetch_waifu "$API_RATING" "$CATEGORY" "$tmpfile")" || true
    if [[ -n "$url" && -s "$tmpfile" ]]; then
        IMAGE_URL="$url"
        IMAGE_FILE="$tmpfile"
        save_cache
        return 0
    fi
    rm -f "$tmpfile" 2>/dev/null || true
    IMAGE_URL=""
    IMAGE_FILE=""
    return 1
}

# ============================================================
# prefetch_cache - download next image in background (bypasses cache)
# ============================================================
prefetch_cache() {
    if [[ ${CAN_CACHE:-0} -eq 1 ]]; then
        (
            local tmpfile url
            tmpfile="$(mktemp /tmp/waifu-prefetch-XXXXXX 2>/dev/null)"
            url="$(fetch_waifu "$API_RATING" "$CATEGORY" "$tmpfile")" || true
            if [[ -n "$url" && -s "$tmpfile" ]]; then
                setup_cache
                printf '%s\n%s\n' "$CACHE_KEY" "$url" > "$CM" 2>/dev/null
                cp "$tmpfile" "$CF" 2>/dev/null
            fi
            rm -f "$tmpfile" 2>/dev/null || true
        ) &
        disown 2>/dev/null || true
    fi
}

# ============================================================
# fetch_waifu - fetch a waifu image from the APIs
# Returns the image URL on stdout (non-empty) and downloads to outfile.
# Returns 0 on success, 1 on failure.
# Uses global: MODE, RATING_LEVEL, IS_DIRECT_RATING, NB_GIFS, NB_STATIC
# ============================================================
fetch_waifu() {
    local rating_param="$1"
    local category="$2"
    local outfile="$3"

    local url=""
    local is_gif=0
    for t in "${NB_GIFS[@]}"; do
        [[ "$t" == "$category" ]] && { is_gif=1; break; }
    done

    # ---- nekosapi v4 (with tag verification) ----
    if [[ -z "$url" && $is_gif -eq 0 ]]; then
        local api_attempt
        for ((api_attempt=0; api_attempt<3; api_attempt++)); do
            local url_param="https://api.nekosapi.com/v4/images/random?limit=1&rating=${rating_param}"
            [[ "$category" != "waifu" ]] && url_param="${url_param}&included_tags=${category}"
            local resp
            resp="$(curl -sL --max-time 5 "$url_param" 2>/dev/null)"
            url="$(printf '%s' "$resp" | jq -r '.[0].url // empty' 2>/dev/null)"
            if [[ -n "$url" && "$category" != "waifu" ]]; then
                # Verify the image actually has the requested tag
                if printf '%s' "$resp" | jq -e ".[0].tags | index(\"$category\")" >/dev/null 2>&1; then
                    break
                else
                    url=""  # Tag mismatch, retry
                fi
            else
                break
            fi
        done
    fi

    # ---- waifu.im fallback ----
    if [[ -z "$url" && $is_gif -eq 0 ]]; then
        local wim_nsf="false"
        [[ "$RATING_LEVEL" == "borderline" || "$RATING_LEVEL" == "explicit" || "$MODE" == "nsfw" ]] && wim_nsf="true"
        [[ $IS_DIRECT_RATING -eq 1 && "$RATING_LEVEL" == "suggestive" ]] && wim_nsf="true"
        local json
        json="$(curl -sL --max-time 5 \
            "https://api.waifu.im/images?IsNsfw=${wim_nsf}&IncludedTags=${category}")"
        if ! printf '%s' "$json" | grep -q "Just a moment\|_cf_chl_opt\|challenge-platform"; then
            url="$(printf '%s' "$json" | jq -r '.items[0].url // empty' 2>/dev/null)"
        fi
    fi

    # ---- nekos.best ----
    if [[ -z "$url" && "$MODE" == "sfw" ]]; then
        if [[ $is_gif -eq 1 ]]; then
            url="$(curl -sL --max-time 8 "https://nekos.best/api/v2/${category}" | \
                jq -r '.results[0].url // empty' 2>/dev/null)"
        else
            local nc="waifu"
            for t in "${NB_STATIC[@]}"; do
                [[ "$t" == "$category" ]] && { nc="$t"; break; }
            done
            url="$(curl -sL --max-time 8 "https://nekos.best/api/v2/${nc}" | \
                jq -r '.results[0].url // empty' 2>/dev/null)"
        fi
    fi

    # ---- nekosapi v4 catch-all ----
    if [[ -z "$url" && $is_gif -eq 0 ]]; then
        url="$(curl -sL --max-time 8 \
            "https://api.nekosapi.com/v4/images/random?limit=1&rating=${rating_param}" | \
            jq -r '.[0].url // empty' 2>/dev/null)"
    fi

    if [[ -z "$url" ]]; then
        return 1
    fi

    curl -sL --max-time 10 "$url" > "$outfile" 2>/dev/null
    if [[ ! -s "$outfile" ]]; then
        rm -f "$outfile"
        return 1
    fi

    printf '%s' "$url"
    return 0
}

# ============================================================
# display_image - display an image in the terminal
# Tries multiple methods, falls back to URL
# ============================================================
display_image() {
    local file="$1"
    local url="$2"
    local preferred="${3:-}"
    local width
    if [[ -n "${COLUMNS:-}" ]]; then
        width="$COLUMNS"
    else
        width="$(tput cols 2>/dev/null || echo 80)"
    fi

    if [[ -n "$preferred" ]]; then
        # User specified a displayer -- only try that one
        case "$preferred" in
            icat)
                if [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == *kitty* ]]; then
                    if command -v kitty &>/dev/null; then
                        [[ $DEBUG -eq 1 ]] && echo "[display] kitty icat" >&2
                        kitty +kitten icat "$file" 2>/dev/null && return 0
                    fi
                fi
                # Fallback: try chafa for icat too (it can display images natively)
                if command -v chafa &>/dev/null; then
                    [[ $DEBUG -eq 1 ]] && echo "[display] chafa (icat fallback)" >&2
                    chafa --symbols=block "$file" 2>/dev/null && return 0
                fi
                ;;
            chafa)
                if command -v chafa &>/dev/null; then
                    [[ $DEBUG -eq 1 ]] && echo "[display] chafa" >&2
                    chafa --symbols=block "$file" 2>/dev/null && return 0
                fi
                ;;
            img2txt)
                if command -v img2txt &>/dev/null; then
                    [[ $DEBUG -eq 1 ]] && echo "[display] img2txt" >&2
                    img2txt -W "$width" "$file" 2>/dev/null | tr -d '\r' | sed \$'s/\x1b\[[su]//g' && return 0
                fi
                ;;
            jp2a)
                if command -v jp2a &>/dev/null; then
                    [[ $DEBUG -eq 1 ]] && echo "[display] jp2a" >&2
                    jp2a --width="$width" "$file" 2>/dev/null && return 0
                fi
                ;;
        esac
        return 1
    fi

    # Auto-detect: no preference specified
    # 1. Kitty native icat
    if [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == *kitty* ]]; then
        if command -v kitty &>/dev/null; then
            [[ $DEBUG -eq 1 ]] && echo "[display] kitty icat" >&2
            kitty +kitten icat "$file" 2>/dev/null && return 0
        fi
    fi

    # 2. chafa - auto-detects sixel/kitty/iterm2, falls back to ANSI blocks
    if command -v chafa &>/dev/null; then
        [[ $DEBUG -eq 1 ]] && echo "[display] chafa" >&2
        chafa --symbols=block "$file" 2>/dev/null && return 0
    fi

    # 3. catimg - block pixel display (works on most terminals)
    if command -v catimg &>/dev/null; then
        [[ $DEBUG -eq 1 ]] && echo "[display] catimg" >&2
        catimg "$file" 2>/dev/null && return 0
    fi

    # 4. viu - multi-protocol rust tool
    if command -v viu &>/dev/null; then
        [[ $DEBUG -eq 1 ]] && echo "[display] viu" >&2
        viu "$file" 2>/dev/null && return 0
    fi

    # 5. img2txt (caca-utils) - colored ASCII art
    # Strip CRLF -> LF + remove cursor save/restore -> no flicker
    if command -v img2txt &>/dev/null; then
        [[ $DEBUG -eq 1 ]] && echo "[display] img2txt" >&2
        img2txt -W "$width" "$file" 2>/dev/null | tr -d '\r' | sed \$'s/\x1b\[[su]//g' && return 0
    fi

    # 6. jp2a - black & white ASCII art
    if command -v jp2a &>/dev/null; then
        [[ $DEBUG -eq 1 ]] && echo "[display] jp2a" >&2
        jp2a --width="$width" "$file" 2>/dev/null && return 0
    fi

    # Last resort: print URL
    [[ $DEBUG -eq 1 ]] && echo "[display] url-only" >&2
    echo "Image: $url"
    echo "Tip: Install 'jp2a' or 'chafa' for terminal image display." >&2
    return 1
}

# ============================================================
# image_to_text - convert image to text lines (for side-by-side display)
# ============================================================
image_to_text() {
    local file="$1"
    local width="$2"
    local max_height="${3:-0}"
    local preferred="${4:-}"
    local lines=()

    local img_width=$((width / 3))
    [[ $img_width -lt 15 ]] && img_width=15
    [[ $img_width -gt 40 ]] && img_width=40

    local img_height=$((img_width * 2 / 3))
    if [[ $max_height -gt 0 ]]; then
        local cap=$((max_height * 2))
        [[ $cap -lt $img_height ]] && img_height=$cap
        [[ $img_height -lt 8 ]] && img_height=8
    fi

    if [[ -n "$preferred" ]]; then
        # User specified a displayer -- only try that one
        case "$preferred" in
            chafa)
                if command -v chafa &>/dev/null; then
                    mapfile -t lines < <(chafa --format=symbols --symbols=block --relative=off --size="${img_width}x${img_height}" "$file" 2>/dev/null || true)
                    if [[ ${#lines[@]} -gt 0 ]]; then
                        printf '%s\n' "${lines[@]}"
                        return 0
                    fi
                fi
                ;;
            img2txt)
                if command -v img2txt &>/dev/null; then
                    mapfile -t lines < <(img2txt -W "$img_width" "$file" 2>/dev/null | tr -d '\r' | sed $'s/\x1b\[[su]//g' || true)
                    if [[ ${#lines[@]} -gt 0 ]]; then
                        printf '%s\n' "${lines[@]}"
                        return 0
                    fi
                fi
                ;;
            jp2a)
                if command -v jp2a &>/dev/null; then
                    mapfile -t lines < <(jp2a --width="$img_width" "$file" 2>/dev/null || true)
                    if [[ ${#lines[@]} -gt 0 ]]; then
                        printf '%s\n' "${lines[@]}"
                        return 0
                    fi
                fi
                ;;
            icat)
                # icat does not output text lines -- handled separately in main()
                return 1
                ;;
        esac
        return 1
    fi

    # No preference: auto-detect
    if command -v chafa &>/dev/null; then
        mapfile -t lines < <(chafa --format=symbols --symbols=block --relative=off --size="${img_width}x${img_height}" "$file" 2>/dev/null || true)
        if [[ ${#lines[@]} -gt 0 ]]; then
            printf '%s\n' "${lines[@]}"
            return 0
        fi
    fi

    if command -v img2txt &>/dev/null; then
        mapfile -t lines < <(img2txt -W "$img_width" "$file" 2>/dev/null | tr -d '\r' | sed $'s/\x1b\[[su]//g' || true)
        if [[ ${#lines[@]} -gt 0 ]]; then
            printf '%s\n' "${lines[@]}"
            return 0
        fi
    fi

    if command -v jp2a &>/dev/null; then
        mapfile -t lines < <(jp2a --width="$img_width" "$file" 2>/dev/null || true)
        if [[ ${#lines[@]} -gt 0 ]]; then
            printf '%s\n' "${lines[@]}"
            return 0
        fi
    fi

    return 1
}

# ============================================================
# print_side_by_side - display art and info columns
# ============================================================
print_side_by_side() {
    local -n _art="$1"
    local -n _info="$2"
    local width="${COLUMNS:-80}"

    local max_art_w=0
    local line clean len
    for line in "${_art[@]}"; do
        clean="$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')"
        len=${#clean}
        [[ $len -gt $max_art_w ]] && max_art_w=$len
    done

    local info_col=$((max_art_w + 2))
    local reset=$'\033[0m'
    local key_color=$'\033[1;36m'
    local info_lines=()
    local i=0 total="${#_info[@]}" key val
    while [[ $i -lt $total ]]; do
        key="${_info[$i]}"
        val="${_info[$((i+1))]:-}"
        info_lines+=("${key_color}${key}:${reset} ${val}")
        i=$((i + 2))
    done

    local max_lines=${#_art[@]}
    local max_info=${#info_lines[@]}
    local max=$((max_lines > max_info ? max_lines : max_info))
    local l art_line info_line

    for ((l=0; l<max; l++)); do
        art_line=""
        info_line=""
        [[ $l -lt ${#_art[@]} ]] && art_line="${_art[$l]}"
        [[ $l -lt ${#info_lines[@]} ]] && info_line="${info_lines[$l]}"

        if [[ -n "$art_line" && -n "$info_line" ]]; then
            printf '%s\033[%dG%s\n' "$art_line" "$info_col" "$info_line"
        elif [[ -n "$art_line" ]]; then
            printf '%s\n' "$art_line"
        elif [[ -n "$info_line" ]]; then
            printf '\033[%dG%s\n' "$info_col" "$info_line"
        fi
    done
}

# ============================================================
# print_info_fallback - plain text info display
# ============================================================
print_info_fallback() {
    local -n _fallback="$1"
    local i=0 total="${#_fallback[@]}" key val
    while [[ $i -lt $total ]]; do
        key="${_fallback[$i]}"
        val="${_fallback[$((i+1))]:-}"
        printf "  %-12s %s\n" "${key}:" "$val"
        i=$((i + 2))
    done
}

# ============================================================
# collect_info - collect system information into an associative array
# ============================================================
collect_info() {
    local -n _ci="$1"
    local os user host uptime_str uptime_secs days hours mins \
          shell term de cpu gpu mem pkgs res swap disk

    os=""
    if [[ -f /etc/os-release ]]; then
        os="$(grep -oP '(?<=^PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null || \
              grep -oP '(?<=^NAME=").*(?=")' /etc/os-release 2>/dev/null || \
              grep -oP '(?<=^NAME=)[^"\n]+' /etc/os-release 2>/dev/null)"
    fi
    [[ -z "$os" ]] && os="$(uname -s)"
    _ci+=("OS" "$os")

    user="$(whoami 2>/dev/null || echo "${USER:-unknown}")"
    host="$(hostname 2>/dev/null || echo "unknown")"
    _ci+=("Host" "${user}@${host}")

    _ci+=("Kernel" "$(uname -r 2>/dev/null || echo 'unknown')")

    uptime_str=""
    if [[ -f /proc/uptime ]]; then
        uptime_secs="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
        days=$((uptime_secs / 86400))
        hours=$(( (uptime_secs % 86400) / 3600 ))
        mins=$(( (uptime_secs % 3600) / 60 ))
        if [[ $days -gt 0 ]]; then
            uptime_str="${days}d ${hours}h ${mins}m"
        elif [[ $hours -gt 0 ]]; then
            uptime_str="${hours}h ${mins}m"
        else
            uptime_str="${mins}m"
        fi
    else
        uptime_str="$(uptime -p 2>/dev/null | sed 's/^up //' || echo 'unknown')"
    fi
    _ci+=("Uptime" "$uptime_str")

    shell="${SHELL:-unknown}"
    shell="$(basename "$shell")"
    _ci+=("Shell" "$shell")

    term="${TERM:-unknown}"
    _ci+=("Terminal" "$term")

    de="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
    if [[ -z "$de" ]]; then
        if command -v wmctrl &>/dev/null; then
            de="$(wmctrl -m 2>/dev/null | grep -oP '(?<=Name: ).*' || true)"
        fi
        [[ -z "$de" ]] && de="$(pgrep -l -x gnome-shell | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x kwin_x11 | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x kwin_wayland | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x sway | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x hyprland | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x i3 | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x bspwm | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x dwm | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x openbox | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x awesome | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x herbstluftwm | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x qtile | grep -oP '^\d+ \K.*' || \
                                 pgrep -l -x xfce4-panel | grep -oP '^\d+ \K.*' || true)"
        [[ -z "$de" ]] && de="Not detected"
    fi
    _ci+=("WM/DE" "$de")

    cpu=""
    if [[ -f /proc/cpuinfo ]]; then
        cpu="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //' || true)"
    fi
    [[ -z "$cpu" ]] && cpu="$(lscpu 2>/dev/null | grep 'Model name' | sed 's/.*:\s*//' || echo 'unknown')"
    cpu="$(printf '%s' "$cpu" | sed 's/(R)//g; s/(TM)//g; s/ CPU @ [0-9.]*GHz//g; s/  */ /g' | xargs)"
    _ci+=("CPU" "$cpu")

    gpu=""
    if command -v lspci &>/dev/null; then
        gpu="$(lspci 2>/dev/null | grep -i 'vga\|3d\|display' | head -1 | sed 's/.*: //; s/ (rev.*)//; s/ \[.*\]//g' || true)"
    fi
    [[ -z "$gpu" ]] && gpu="unknown"
    gpu="$(printf '%s' "$gpu" | sed 's/ \(Corporation\|Technology\|Inc\)//g' | xargs)"
    _ci+=("GPU" "$gpu")

    mem=""
    if command -v free &>/dev/null; then
        mem="$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}')"
    fi
    [[ -z "$mem" ]] && mem="unknown"
    _ci+=("Memory" "$mem")

    swap=""
    if command -v free &>/dev/null; then
        swap="$(free -h 2>/dev/null | awk '/^Swap:/ {print $3 "/" $2}')"
    fi
    [[ -z "$swap" || "$swap" == "/" ]] && swap="none"
    _ci+=("Swap" "$swap")

    disk=""
    if command -v df &>/dev/null; then
        disk="$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    fi
    [[ -z "$disk" ]] && disk="unknown"
    _ci+=("Disk" "$disk")

    pkgs=0
    if command -v pacman &>/dev/null; then
        pkgs=$((pkgs + $(pacman -Q 2>/dev/null | wc -l)))
    fi
    if command -v dpkg &>/dev/null; then
        pkgs=$((pkgs + $(dpkg -l 2>/dev/null | wc -l)))
    fi
    if command -v rpm &>/dev/null; then
        pkgs=$((pkgs + $(rpm -qa 2>/dev/null | wc -l)))
    fi
    if command -v flatpak &>/dev/null; then
        pkgs=$((pkgs + $(flatpak list 2>/dev/null | wc -l)))
    fi
    if [[ $pkgs -gt 0 ]]; then
        _ci+=("Packages" "$pkgs")
    fi

    res=""
    if command -v xrandr &>/dev/null; then
        res="$(xrandr 2>/dev/null | grep ' connected' | head -1 | grep -oP '\d+x\d+\s*\d+\.\d+\*?' | head -1 | awk '{print $1}' || true)"
    fi
    if [[ -z "$res" && -d /sys/class/drm ]]; then
        res="$(cat /sys/class/drm/*/modes 2>/dev/null | head -1 || true)"
    fi
    if command -v wlr-randr &>/dev/null; then
        res="$(wlr-randr 2>/dev/null | grep -oP '\d+x\d+ px' | head -1 | sed 's/ px//' || true)"
    fi
    [[ -n "$res" ]] && _ci+=("Resolution" "$res")
}

# ============================================================
# nsfw_help - print NSFW-specific help
# ============================================================
nsfw_help() {
    local prog="${1:-waifu}"
    cat <<EOF
=== NSFW mode ===
Usage: $prog [displayer] [category|rating] [tag] [--noLink] [--debug]

  $prog nsfw [tag]                   - NSFW (borderline + explicit)
  $prog borderline [tag]             - exact: borderline only
  $prog explicit [tag]               - exact: explicit only
  $prog suggestive [tag]             - exact: suggestive only

  $prog icat nsfw                    - force kitty icat with NSFW
  $prog chafa explicit neko          - force chafa with explicit + tag

  $prog --setDefaultDisplayer <d>    - set default image displayer
                                       Valid: icat, chafa, img2txt, jp2a

  $prog -i <file>                    - display a local image/GIF file
  $prog --noLink                     - suppress image URL output
  $prog --debug                      - show detailed debug info

Displayers: icat, chafa, img2txt, jp2a
  icat     native image display (kitty terminal)
  chafa    colored text-art via chafa library
  img2txt  colored ASCII art (caca-utils)
  jp2a     black & white ASCII art
  (default: auto-detect)

NSFW tags:  ero, ecchi, hentai, oppai, ass, milf, oral, paizuri
SFW tags:   waifu, neko, kitsune, husbando, maid, uniform, selfies
Characters: raiden-shogun, mori-calliope, rem, marin-kitagawa,
            genshin-impact, kamisato-ayaka
GIFs:       lurk, shoot, sleep, clap, shrug, stare, wave, poke,
            confused, smile, peck, wink, sip, blush, smug, tickle,
            yeet, think, highfive, feed, wag, bite

Ratings: safe, suggestive, borderline, explicit (cascading)
  borderline includes: safe + suggestive + borderline content
  nsfw mode uses: borderline + explicit

Default SFW rating: $DEFAULT_SFW
  Set with: $prog --setDefaultSFW <safe|suggestive|borderline>

Default displayer: ${DEFAULT_DISPLAYER:-auto}
  Set with: $prog --setDefaultDisplayer <icat|chafa|img2txt|jp2a>

APIs: nekosapi.com v4, waifu.im, nekos.best
Note: Tag/rating filtering depends on API metadata and is not 100%
      precise. You may occasionally see unexpected content.
EOF
    exit 0
}

# ============================================================
# usage - print main help text
# ============================================================
usage() {
    local prog="${1:-waifu}"
    cat <<EOF
Usage: $prog [displayer] [category|rating] [tag] [--debug]
  $prog                              - default SFW ($DEFAULT_SFW)
  $prog sfw [tag]                    - SFW (default rating, cascading)
  $prog nsfw [tag]                   - NSFW (borderline + explicit)
  $prog safe [tag]                   - exact: safe only
  $prog suggestive [tag]             - exact: suggestive only
  $prog borderline [tag]             - exact: borderline only
  $prog explicit [tag]               - exact: explicit only

  $prog icat                         - force kitty icat display
  $prog chafa suggestive             - force chafa with rating
  $prog jp2a borderline neko         - force jp2a with rating + tag

  $prog --setDefaultSFW <r>          - set default SFW rating
                                       Valid: safe, suggestive,
                                       borderline (cascades:
                                       borderline includes all
                                       safe + suggestive + borderline)

  $prog --setDefaultDisplayer <d>    - set default image displayer
                                       Valid: icat, chafa, img2txt, jp2a

  $prog -i <file>                    - display a local image/GIF file
  $prog --noLink                     - suppress image URL output
  $prog --debug                      - show detailed debug info
  $prog -v, --version                - show version and exit
  $prog nsfw --help                  - show NSFW-specific help

Displayers: icat, chafa, img2txt, jp2a
  icat     native image display (kitty terminal)
  chafa    colored text-art via chafa library
  img2txt  colored ASCII art (caca-utils)
  jp2a     black & white ASCII art
  (default: auto-detect)

Categories: waifu, neko, kitsune, husbando, maid, uniform, selfies
Characters: raiden-shogun, mori-calliope, rem, marin-kitagawa,
           genshin-impact, kamisato-ayaka
GIFs:      lurk, shoot, sleep, clap, shrug, stare, wave, poke,
           confused, smile, peck, wink, sip, blush, smug, tickle,
           yeet, think, highfive, feed, wag, bite

APIs used: nekosapi.com v4, waifu.im, nekos.best
Note: Tags and ratings depend on API metadata and are not 100% precise.
      You may occasionally see unexpected content.
EOF
    exit 0
}

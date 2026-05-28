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
# Cross-platform helpers
# ============================================================

# _mktemp - temporary file (works on Linux, macOS, BSD)
_mktemp() {
    mktemp -t waifu-tmp 2>/dev/null || mktemp 2>/dev/null
}

# _mktemp_dir - temporary directory (works on Linux, macOS, BSD)
_mktemp_dir() {
    mktemp -d -t waifu-dir 2>/dev/null || mktemp -d 2>/dev/null
}

# _human_size - convert bytes to human-readable (e.g., 1073741824 -> 1G)
_human_size() {
    local bytes=$1 irate
    irate=$(awk -v b="$bytes" 'BEGIN {
        if (b >= 1073741824)  printf "%.1fG\n", b/1073741824;
        else if (b >= 1048576) printf "%.1fM\n", b/1048576;
        else if (b >= 1024)    printf "%.1fK\n", b/1024;
        else                   printf "%dB\n", b;
    }' 2>/dev/null)
    echo "${irate}"
}

# _uptime_secs - get seconds since boot (cross-platform)
_uptime_secs() {
    if [[ -f /proc/uptime ]]; then
        awk '{print int($1)}' /proc/uptime 2>/dev/null
    elif command -v sysctl &>/dev/null; then
        local boottime
        boottime="$(sysctl -n kern.boottime 2>/dev/null | sed 's/[^0-9 ]//g' | awk '{print $1}' 2>/dev/null || true)"
        if [[ -n "$boottime" && "$boottime" -gt 0 ]]; then
            echo $(( $(date +%s) - boottime ))
        fi
    fi
}

# ============================================================
# is_gif_file - check if a file is an animated GIF
# ============================================================
is_gif_file() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    # Bash 3.2 compat: no ${f,,} available, use tr for lowercasing
    if echo "${f##*.}" | grep -iq '^gif$'; then
        return 0
    fi
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
    tmpfile="$(_mktemp)"
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
            tmpfile="$(_mktemp)"
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
# _readlines - read command output into array (bash 3.2 compat, no mapfile)
# Usage: _readlines array_name < <(command)
# ============================================================
_readlines() {
    local _r_name="$1"
    local _r_line
    eval "$_r_name=()"
    while IFS= read -r _r_line; do
        eval "$_r_name[\${#$_r_name[@]}]=\$_r_line"
    done
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
                    _readlines lines < <(chafa --format=symbols --symbols=block --relative=off --size="${img_width}x${img_height}" "$file" 2>/dev/null || true)
                    if [[ ${#lines[@]} -gt 0 ]]; then
                        printf '%s\n' "${lines[@]}"
                        return 0
                    fi
                fi
                ;;
            img2txt)
                if command -v img2txt &>/dev/null; then
                    _readlines lines < <(img2txt -W "$img_width" "$file" 2>/dev/null | tr -d '\r' | sed $'s/\x1b\[[su]//g' || true)
                    if [[ ${#lines[@]} -gt 0 ]]; then
                        printf '%s\n' "${lines[@]}"
                        return 0
                    fi
                fi
                ;;
            jp2a)
                if command -v jp2a &>/dev/null; then
                    _readlines lines < <(jp2a --width="$img_width" "$file" 2>/dev/null || true)
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
        _readlines lines < <(chafa --format=symbols --symbols=block --relative=off --size="${img_width}x${img_height}" "$file" 2>/dev/null || true)
        if [[ ${#lines[@]} -gt 0 ]]; then
            printf '%s\n' "${lines[@]}"
            return 0
        fi
    fi

    if command -v img2txt &>/dev/null; then
        _readlines lines < <(img2txt -W "$img_width" "$file" 2>/dev/null | tr -d '\r' | sed $'s/\x1b\[[su]//g' || true)
        if [[ ${#lines[@]} -gt 0 ]]; then
            printf '%s\n' "${lines[@]}"
            return 0
        fi
    fi

    if command -v jp2a &>/dev/null; then
        _readlines lines < <(jp2a --width="$img_width" "$file" 2>/dev/null || true)
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
# Args: $1=art_array_name $2=info_array_name
# Compatible with bash 3.2 (macOS) — no namerefs.
print_side_by_side() {
    local _art_name="$1" _info_name="$2"
    local width="${COLUMNS:-80}"

    # Retrieve array length via eval (bash 3.2 compat, no nameref)
    local _art_len _info_len
    eval "_art_len=\${#$_art_name[@]}"
    eval "_info_len=\${#$_info_name[@]}"

    local max_art_w=0
    local line clean len
    local i
    for ((i=0; i<_art_len; i++)); do
        eval "line=\${$_art_name[\$i]}"
        clean="$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')"
        len=${#clean}
        [[ $len -gt $max_art_w ]] && max_art_w=$len
    done

    local info_col=$((max_art_w + 2))
    local reset=$'\033[0m'
    local key_color=$'\033[1;36m'
    local info_lines=()
    local j=0 key val
    while [[ $j -lt $_info_len ]]; do
        eval "key=\${$_info_name[\$j]}"
        eval "val=\${$_info_name[\$((j+1))]:-}"
        info_lines+=("${key_color}${key}:${reset} ${val}")
        j=$((j + 2))
    done

    local max_lines=$_art_len
    local max_info=${#info_lines[@]}
    local max=$((max_lines > max_info ? max_lines : max_info))
    local l art_line info_line

    for ((l=0; l<max; l++)); do
        art_line=""
        info_line=""
        if [[ $l -lt $_art_len ]]; then
            eval "art_line=\${$_art_name[\$l]}"
        fi
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
# Args: $1=array_name — compatible with bash 3.2 (macOS).
print_info_fallback() {
    local _arr_name="$1"
    local _total
    eval "_total=\${#$_arr_name[@]}"
    local i=0 key val
    while [[ $i -lt $_total ]]; do
        eval "key=\${$_arr_name[\$i]}"
        eval "val=\${$_arr_name[\$((i+1))]:-}"
        printf "  %-12s %s\n" "${key}:" "$val"
        i=$((i + 2))
    done
}

# ============================================================
# collect_info - collect system information (Linux, macOS, BSD)
# Stores results into a global array INFO_PAIRS.
# Compatible with bash 3.2 (macOS) — no namerefs.
# ============================================================
INFO_PAIRS=()
collect_info() {
    INFO_PAIRS=()
    local os user host uptime_str uptime_secs days hours mins \
          shell term de cpu gpu mem swap disk pkgs res

    local uname_s="$(uname -s 2>/dev/null || echo 'unknown')"
    local uname_r="$(uname -r 2>/dev/null || echo 'unknown')"

    # ---- OS ----
    os=""
    if [[ -f /etc/os-release ]]; then
        os="$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release 2>/dev/null || \
              sed -n 's/^NAME="\(.*\)"/\1/p' /etc/os-release 2>/dev/null || \
              sed -n 's/^NAME=\([^"]*\)/\1/p' /etc/os-release 2>/dev/null)"
    fi
    if [[ -z "$os" ]]; then
        case "$uname_s" in
            Darwin)  os="macOS $(sw_vers -productVersion 2>/dev/null || true)" ;;
            FreeBSD) os="FreeBSD $uname_r" ;;
            OpenBSD) os="OpenBSD $uname_r" ;;
            NetBSD)  os="NetBSD $uname_r" ;;
            *)       os="$uname_s" ;;
        esac
    fi
    INFO_PAIRS+=("OS" "$os")

    # ---- Host ----
    user="$(whoami 2>/dev/null || echo "${USER:-unknown}")"
    host="$(hostname 2>/dev/null || echo "unknown")"
    INFO_PAIRS+=("Host" "${user}@${host}")

    # ---- Kernel ----
    INFO_PAIRS+=("Kernel" "$uname_r")

    # ---- Uptime ----
    uptime_str=""
    uptime_secs="$(_uptime_secs)"
    if [[ -n "$uptime_secs" && "$uptime_secs" -gt 0 ]]; then
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
    fi
    if [[ -z "$uptime_str" ]]; then
        # fallback: parse uptime output (varies by OS)
        local raw_uptime
        raw_uptime="$(uptime 2>/dev/null | sed 's/.* up *//; s/,.*//; s/\s\+/ /g' | xargs || true)"
        if echo "$raw_uptime" | grep -qE '^[0-9]+:[0-9]+'; then
            local uh um
            uh="${raw_uptime%%:*}"
            um="${raw_uptime#*:}"
            um="${um%% *}"
            if [[ "$uh" -gt 24 ]]; then
                uptime_str="${uh}m"
            else
                uptime_str="${uh}h ${um}m"
            fi
        elif [[ -n "$raw_uptime" ]]; then
            uptime_str="$raw_uptime"
        else
            uptime_str="unknown"
        fi
    fi
    INFO_PAIRS+=("Uptime" "$uptime_str")

    # ---- Shell ----
    shell="${SHELL:-unknown}"
    shell="$(basename "$shell")"
    INFO_PAIRS+=("Shell" "$shell")

    # ---- Terminal ----
    term="${TERM:-unknown}"
    INFO_PAIRS+=("Terminal" "$term")

    # ---- WM/DE ----
    de="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
    if [[ -z "$de" ]]; then
        if command -v wmctrl &>/dev/null; then
            de="$(wmctrl -m 2>/dev/null | sed -n 's/.*Name: //p' || true)"
        fi
        [[ -z "$de" ]] && de="$(pgrep -l -x gnome-shell | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x kwin_x11 | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x kwin_wayland | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x sway | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x hyprland | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x i3 | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x bspwm | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x dwm | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x openbox | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x awesome | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x herbstluftwm | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x qtile | sed -n 's/^[0-9]* //p' || \
                                 pgrep -l -x xfce4-panel | sed -n 's/^[0-9]* //p' || true)"
    fi
    if [[ -z "$de" && "$uname_s" == "Darwin" ]]; then
        de="Aqua"
    fi
    [[ -z "$de" ]] && de="Not detected"
    INFO_PAIRS+=("WM/DE" "$de")

    # ---- CPU ----
    cpu=""
    if [[ -f /proc/cpuinfo ]]; then
        cpu="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //' || true)"
    fi
    if [[ -z "$cpu" ]] && command -v sysctl &>/dev/null; then
        cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || \
               sysctl -n hw.model 2>/dev/null || true)"
    fi
    [[ -z "$cpu" ]] && cpu="$uname_s $uname_r"
    cpu="$(printf '%s' "$cpu" | sed 's/(R)//g; s/(TM)//g; s/ CPU @ [0-9.]*GHz//g; s/  */ /g' | xargs)"
    INFO_PAIRS+=("CPU" "$cpu")

    # ---- GPU ----
    gpu=""
    if command -v lspci &>/dev/null; then
        gpu="$(lspci 2>/dev/null | grep -i 'vga\|3d\|display' | head -1 | sed 's/.*: //; s/ (rev.*)//; s/ \[.*\]//g' || true)"
    fi
    if [[ -z "$gpu" && "$uname_s" == "Darwin" ]] && command -v system_profiler &>/dev/null; then
        gpu="$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/ {print $2; exit}' || true)"
    fi
    [[ -z "$gpu" ]] && gpu="unknown"
    gpu="$(printf '%s' "$gpu" | sed 's/ \(Corporation\|Technology\|Inc\)//g' | xargs)"
    INFO_PAIRS+=("GPU" "$gpu")

    # ---- Memory ----
    mem=""
    if command -v free &>/dev/null; then
        mem="$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}')"
    elif [[ "$uname_s" == "Darwin" ]] && command -v vm_stat &>/dev/null; then
        local mem_total mem_used page_size active_pages wire_pages
        mem_total="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
        page_size="$(sysctl -n hw.pagesize 2>/dev/null)"
        [[ -z "$page_size" || "$page_size" -eq 0 ]] && page_size=16384
        active_pages="$(vm_stat 2>/dev/null | awk '/Pages active/  {gsub(/[^0-9]/,"",$NF); print $NF; exit}')"
        wire_pages="$(vm_stat 2>/dev/null | awk '/Pages wired/   {gsub(/[^0-9]/,"",$NF); print $NF; exit}')"
        [[ -z "$active_pages" ]] && active_pages=0
        [[ -z "$wire_pages" ]] && wire_pages=0
        mem_used="$(( (active_pages + wire_pages) * page_size ))"
        mem="$(_human_size "$mem_used")/$(_human_size "$mem_total")"
    elif command -v sysctl &>/dev/null; then
        mem_total="$(sysctl -n hw.physmem 2>/dev/null)"
        [[ -n "$mem_total" ]] && mem="$(_human_size "$mem_total")"
    fi
    [[ -z "$mem" ]] && mem="unknown"
    INFO_PAIRS+=("Memory" "$mem")

    # ---- Swap ----
    swap=""
    if command -v free &>/dev/null; then
        swap="$(free -h 2>/dev/null | awk '/^Swap:/ {print $3 "/" $2}')"
    elif [[ "$uname_s" == "Darwin" ]]; then
        swap="$(sysctl -n vm.swapusage 2>/dev/null | awk '{gsub(/[=,]/," "); print $4 "/" $2}' || true)"
    fi
    [[ -z "$swap" || "$swap" == "/" ]] && swap="none"
    INFO_PAIRS+=("Swap" "$swap")

    # ---- Disk ----
    disk=""
    if command -v df &>/dev/null; then
        disk="$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    fi
    [[ -z "$disk" ]] && disk="unknown"
    INFO_PAIRS+=("Disk" "$disk")

    # ---- Packages ----
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
    if command -v snap &>/dev/null; then
        pkgs=$((pkgs + $(snap list 2>/dev/null | wc -l)))
    fi
    if [[ -d /var/db/pkg ]]; then
        # Gentoo portage (count installed slots, works without extra tools)
        pkgs=$((pkgs + $(ls -d /var/db/pkg/*/* 2>/dev/null | wc -l)))
    fi
    if command -v apk &>/dev/null; then
        pkgs=$((pkgs + $(apk info 2>/dev/null | wc -l)))
    fi
    if command -v xbps-query &>/dev/null; then
        pkgs=$((pkgs + $(xbps-query -l 2>/dev/null | wc -l)))
    fi
    if command -v eopkg &>/dev/null; then
        pkgs=$((pkgs + $(eopkg list-installed 2>/dev/null | wc -l)))
    fi
    if command -v opkg &>/dev/null; then
        pkgs=$((pkgs + $(opkg list-installed 2>/dev/null | wc -l)))
    fi
    if command -v nix-env &>/dev/null; then
        pkgs=$((pkgs + $(nix-env -q 2>/dev/null | wc -l)))
    fi
    if command -v guix &>/dev/null; then
        pkgs=$((pkgs + $(guix package --list-installed 2>/dev/null | wc -l)))
    fi
    if command -v brew &>/dev/null; then
        pkgs=$((pkgs + $(brew list 2>/dev/null | wc -l)))
    fi
    if command -v port &>/dev/null; then
        pkgs=$((pkgs + $(port installed 2>/dev/null | wc -l)))
    fi
    if command -v pkg &>/dev/null; then
        pkgs=$((pkgs + $(pkg info 2>/dev/null | wc -l)))
    fi
    if command -v pkg_info &>/dev/null; then
        pkgs=$((pkgs + $(pkg_info 2>/dev/null | wc -l)))
    fi
    if [[ $pkgs -gt 0 ]]; then
        INFO_PAIRS+=("Packages" "$pkgs")
    fi

    # ---- Resolution ----
    res=""
    if command -v xrandr &>/dev/null; then
        res="$(xrandr 2>/dev/null | grep ' connected' | head -1 | grep -oE '[0-9]+x[0-9]+' | head -1 || true)"
    fi
    if [[ -z "$res" && -d /sys/class/drm ]]; then
        res="$(cat /sys/class/drm/*/modes 2>/dev/null | head -1 || true)"
    fi
    if command -v wlr-randr &>/dev/null; then
        res="$(wlr-randr 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | head -1 || true)"
    fi
    if [[ -z "$res" && "$uname_s" == "Darwin" ]] && command -v system_profiler &>/dev/null; then
        res="$(system_profiler SPDisplaysDataType 2>/dev/null | grep Resolution | head -1 | sed 's/.*: *//; s/ (.*//; s/ x /x/' || true)"
    fi
    [[ -n "$res" ]] && INFO_PAIRS+=("Resolution" "$res")
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
                                       (empty value "" to clear / auto-detect)
  $prog --setDefaultSFW <r>          - set default SFW rating
                                       Valid: safe, suggestive, borderline
                                       (empty value "" to reset to default)
  $prog --resetSettings              - remove all saved settings and config files

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
  Reset with: $prog --setDefaultSFW ""

Default displayer: ${DEFAULT_DISPLAYER:-auto}
  Set with: $prog --setDefaultDisplayer <icat|chafa|img2txt|jp2a>
  Clear with: $prog --setDefaultDisplayer ""

APIs: nekosapi.com v4, waifu.im, nekos.best
Note: Tag/rating filtering depends on API metadata and is not 100%
      precise. You may occasionally see unexpected content.

Report issues: <https://github.com/JGH0/waifufetch/issues>
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
                                       (empty value "" to reset to default)

  $prog --setDefaultDisplayer <d>    - set default image displayer
                                       Valid: icat, chafa, img2txt, jp2a
                                       (empty value "" to clear / auto-detect)
  $prog --resetSettings              - remove all saved settings and config files

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

Report issues: <https://github.com/JGH0/waifufetch/issues>
EOF
    exit 0
}

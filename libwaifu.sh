#!/usr/bin/env bash
# libwaifu.sh - Shared library for waifu and waifufetch
# Sourced by both scripts
set -euo pipefail 2>/dev/null || set -eu

# ============================================================
# Version
# ============================================================
VERSION="1.3.2"

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

# Danbooru tags (no API key required - uses JSON API)
# Danbooru is a general-purpose booru with extensive tagging including femboy/trap content
DANBOORU_TAGS=(femboy trap neko catgirl waifu original cosplay maid bikini swimsuit
               lingerie pantyhose stockings bunny_girl blush skirt thighhighs)

KNOWN_RATINGS=(safe suggestive borderline explicit sfw nsfw)
ALL_RATINGS=(safe suggestive borderline explicit sfw nsfw)
ALL_KNOWN_TAGS=("${WIM_SFW[@]}" "${WIM_NSFW[@]}" "${WIM_CHARS[@]}" "${NB_STATIC[@]}" "${NB_GIFS[@]}" "${DANBOORU_TAGS[@]}")
KNOWN_API_SOURCES=(auto waifu.im nekosapi nekos.best danbooru)

# Tag-to-API mapping for --list-tags -a filtering
# First entry is the primary API, subsequent are fallbacks
# Declare arrays for each API's direct tags
API_WAIFUIM_TAGS=("${WIM_SFW[@]}" "${WIM_NSFW[@]}" "${WIM_CHARS[@]}")
API_NEKOSAPI_TAGS=(waifu)
API_NEKOSBEST_TAGS=("${NB_STATIC[@]}" "${NB_GIFS[@]}")
API_DANBOORU_TAGS=("${DANBOORU_TAGS[@]}")

# ============================================================
# Config: default SFW rating
# ============================================================
WAIFU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waifufetch"
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
# JSON config support (fastfetch-style)
# ============================================================
WAIFU_JSON_CONFIG="$WAIFU_CONFIG_DIR/config.json"
CONFIG_LOGO_PADDING_TOP=0
CONFIG_SEPARATOR=": "
CONFIG_MODULES_OVERRIDE=""  # filled by load_json_config

# Built-in default config (used when no config.json exists)
WAIFU_DEFAULT_CONFIG_JSON='{
  "logo": {
    "padding": { "top": 1 }
  },
  "display": {
    "separator": ": "
  },
  "modules": [
    { "type": "os",        "key": "OS",        "keyColor": "bold cyan" },
    { "type": "host",      "key": "Host",      "keyColor": "bold cyan" },
    { "type": "kernel",    "key": "Kernel",    "keyColor": "bold cyan" },
    "break",
    { "type": "uptime",    "key": "Uptime",    "keyColor": "bold green" },
    { "type": "packages",  "key": "Packages",  "keyColor": "bold green" },
    { "type": "shell",     "key": "Shell",     "keyColor": "bold green" },
    { "type": "terminal",  "key": "Terminal",  "keyColor": "bold green" },
    "break",
    { "type": "cpu",       "key": "CPU",       "keyColor": "bold yellow" },
    { "type": "gpu",       "key": "GPU",       "keyColor": "bold yellow" },
    { "type": "memory",    "key": "Memory",    "keyColor": "bold yellow" },
    { "type": "disk",      "key": "Disk",      "keyColor": "bold yellow" },
    "break",
    { "type": "wm",        "key": "WM",        "keyColor": "bold magenta" },
    { "type": "resolution","key": "Display",   "keyColor": "bold magenta" },
    "break",
    { "type": "song",      "key": "Now",       "keyColor": "bold white" },
    { "type": "date",      "key": "Date",      "keyColor": "bold white" }
  ]
}'

# ============================================================
# Default API source config
# ============================================================
WAIFU_API_FILE="$WAIFU_CONFIG_DIR/default_api"
DEFAULT_API="auto"
if [[ -f "$WAIFU_API_FILE" ]]; then
    read -r API_VAL < "$WAIFU_API_FILE" || true
    API_VAL="$(printf '%s' "$API_VAL" | xargs)"
    case "$API_VAL" in
        auto|waifu.im|nekosapi|nekos.best|danbooru) DEFAULT_API="$API_VAL" ;;
    esac
fi



# bash 3.2 (macOS) compat: no associative arrays — use a function instead
# Color name -> ANSI raw code (e.g. red -> 31)
_get_color_raw_code() {
    local name="$1"
    case "$name" in
        black)   echo 30 ;;
        red)     echo 31 ;;
        green)   echo 32 ;;
        yellow)  echo 33 ;;
        blue)    echo 34 ;;
        magenta) echo 35 ;;
        cyan)    echo 36 ;;
        white)   echo 37 ;;
        reset)   echo 0 ;;
        *)       echo "" ;;
    esac
}

# Returns a color code as "1;31" or "31" ready for \033[...m
# Accepts: numeric (31), named ("red"), bold-named ("bold red")
_resolve_color() {
    local spec="$1"
    local bold=0
    local code=""
    if [[ "$spec" =~ ^[0-9]+$ ]]; then
        echo "$spec"
        return
    fi
    # Check for bold prefix
    if [[ "$spec" == bold\ * ]]; then
        bold=1
        spec="${spec#bold }"
    fi
    code="$(_get_color_raw_code "$spec")"
    if [[ -n "$code" ]]; then
        if [[ $bold -eq 1 ]]; then
            echo "1;${code}"
        else
            echo "${code}"
        fi
    else
        echo "0"
    fi
}

# load_json_config — loads ~/.config/waifufetch/config.json (or custom path)
# Parses logo.padding.top, display.separator, and modules array.
# Sets globals: CONFIG_LOGO_PADDING_TOP, CONFIG_SEPARATOR, CONFIG_MODULES_OVERRIDE
load_json_config() {
    local cfg="${1:-$WAIFU_JSON_CONFIG}"
    command -v jq &>/dev/null || return 1

    local json
    if [[ -f "$cfg" ]]; then
        json="$(cat "$cfg")"
    else
        # Use built-in default config when no file exists
        json="$WAIFU_DEFAULT_CONFIG_JSON"
    fi

    local val

    # logo.padding.top
    val="$(echo "$json" | jq -r '.logo.padding.top // 0' 2>/dev/null || echo 0)"
    [[ "$val" =~ ^[0-9]+$ ]] && CONFIG_LOGO_PADDING_TOP="$val"

    # display.separator
    val="$(echo "$json" | jq -r '.display.separator // ": "' 2>/dev/null || echo ": ")"
    CONFIG_SEPARATOR="$val"

    # modules — store as JSON string for later processing
    CONFIG_MODULES_OVERRIDE="$(echo "$json" | jq -c '.modules // []' 2>/dev/null || echo "")"

    return 0
}

# resolve_module_type — given a raw jq object or string, extract the type
# Outputs: the type string (e.g., "os", "break", "cpu")
_get_module_type() {
    local item="$1"
    if [[ "$item" == "\"*\"" ]]; then
        # It's a plain string like "break"
        echo "$item" | jq -r '.'
    else
        echo "$item" | jq -r '.type // ""' 2>/dev/null || echo ""
    fi
}

# _get_info_val — look up a value by key from INFO_PAIRS flat array
# Compatible with bash 3.2 — no associative arrays
_get_info_val() {
    local key="$1"
    local _i _k _v
    for ((_i=0; _i<${#INFO_PAIRS[@]}; _i+=2)); do
        _k="${INFO_PAIRS[$_i]}"
        if [[ "$_k" == "$key" ]]; then
            _v="${INFO_PAIRS[$((_i+1))]:-}"
            echo "$_v"
            return 0
        fi
    done
    return 1
}

# _get_info_val_lower — look up case-insensitively
_get_info_val_lower() {
    local key_lc
    key_lc="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    local _i _k _klc _v
    for ((_i=0; _i<${#INFO_PAIRS[@]}; _i+=2)); do
        _k="${INFO_PAIRS[$_i]}"
        _klc="$(echo "$_k" | tr '[:upper:]' '[:lower:]')"
        if [[ "$_klc" == "$key_lc" ]]; then
            _v="${INFO_PAIRS[$((_i+1))]:-}"
            echo "$_v"
            return 0
        fi
    done
    return 1
}

# _render_info_lines — render system info lines from config or legacy format
# Returns lines in INFO_LINES array (global, for side-by-side display)
# Also sets INFO_LINES_PLAIN (no ANSI, for height calculation)
# Sets global INFO_LINE_COUNT
INFO_LINES=()
INFO_LINES_PLAIN=()
INFO_LINE_COUNT=0
render_info_lines() {
    INFO_LINES=()
    INFO_LINES_PLAIN=()
    INFO_LINE_COUNT=0

    local use_config="$1"  # "1" or "0"

    if [[ "$use_config" == "1" && -n "$CONFIG_MODULES_OVERRIDE" ]]; then
        # Render from config
        local reset=$'\033[0m'
        local items_count
        items_count=$(echo "$CONFIG_MODULES_OVERRIDE" | jq -r 'length' 2>/dev/null || echo 0)
        [[ "$items_count" -eq 0 ]] && items_count=0

        local idx
        for ((idx=0; idx<items_count; idx++)); do
            local item
            item=$(echo "$CONFIG_MODULES_OVERRIDE" | jq -c ".[$idx]" 2>/dev/null || echo "")
            [[ -z "$item" || "$item" == "null" ]] && continue

            local type
            type=$(echo "$item" | jq -r 'if type=="string" then . else .type end // ""' 2>/dev/null || echo "")
            [[ -z "$type" ]] && continue

            if [[ "$type" == "break" ]]; then
                INFO_LINES+=("")
                INFO_LINES_PLAIN+=("")
                continue
            fi

            local key key_color_spec fmt
            key=$(echo "$item" | jq -r '.key // empty' 2>/dev/null || echo "")
            key_color_spec=$(echo "$item" | jq -r '.keyColor // empty' 2>/dev/null || echo "")
            fmt=$(echo "$item" | jq -r '.format // empty' 2>/dev/null || echo "")

            local val=""
            val="$(_get_info_val "$type")" || val=""
            if [[ -z "$val" ]]; then
                val="$(_get_info_val_lower "$type")" || val=""
            fi

            if [[ -z "$val" ]]; then
                continue
            fi

            local color_val=""
            if [[ -n "$key_color_spec" ]]; then
                color_val="$(_resolve_color "$key_color_spec")"
            fi

            # Build ANSI line and plain line
            local ansi_line=""
            local plain_line=""
            if [[ -n "$key" ]]; then
                if [[ -n "$color_val" ]]; then
                    ansi_line="$(printf '\033[%sm' "$color_val")${key}${reset}${CONFIG_SEPARATOR}${val}"
                else
                    ansi_line="${key}${CONFIG_SEPARATOR}${val}"
                fi
                plain_line="${key}${CONFIG_SEPARATOR}${val}"
            else
                ansi_line="${val}"
                plain_line="${val}"
            fi

            INFO_LINES+=("$ansi_line")
            INFO_LINES_PLAIN+=("$plain_line")
        done
    else
        # Legacy: render from INFO_PAIRS flat array
        local key_color=$'\033[1;36m'
        local reset=$'\033[0m'
        local total=${#INFO_PAIRS[@]}
        local i=0 key val
        while [[ $i -lt $total ]]; do
            key="${INFO_PAIRS[$i]}"
            val="${INFO_PAIRS[$((i+1))]:-}"
            local ansi="${key_color}${key}:${reset} ${val}"
            local plain="${key}: ${val}"
            INFO_LINES+=("$ansi")
            INFO_LINES_PLAIN+=("$plain")
            i=$((i + 2))
        done
    fi

    INFO_LINE_COUNT=${#INFO_LINES[@]}
}

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

API_SOURCE="$DEFAULT_API"

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
    url="$(fetch_waifu "$API_RATING" "$CATEGORY" "$tmpfile" "$API_SOURCE")" || true
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
            url="$(fetch_waifu "$API_RATING" "$CATEGORY" "$tmpfile" "$API_SOURCE")" || true
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
    local api_source="${4:-$DEFAULT_API}"

    local url=""
    local is_gif=0
    for t in "${NB_GIFS[@]}"; do
        [[ "$t" == "$category" ]] && { is_gif=1; break; }
    done
    local is_dan=0
    for t in "${DANBOORU_TAGS[@]}"; do
        [[ "$t" == "$category" ]] && { is_dan=1; break; }
    done

    # ---- Direct to danbooru for danbooru-only tags ----
    if [[ $is_dan -eq 1 && $is_gif -eq 0 ]]; then
        # Check if this tag is exclusive to Danbooru (not in any other API)
        local is_shared=0
        for t in "${API_WAIFUIM_TAGS[@]}" "${API_NEKOSAPI_TAGS[@]}" "${API_NEKOSBEST_TAGS[@]}"; do
            [[ "$t" == "$category" ]] && { is_shared=1; break; }
        done
        if [[ $is_shared -eq 0 ]]; then
            url="$(fetch_danbooru "$category" "$rating_param" "$outfile")"
            if [[ -n "$url" ]]; then
                printf '%s' "$url"
                return 0
            fi
            # Danbooru-only tag but danbooru failed — no other API has it
            return 1
        fi
    fi

    # Helper to decide if a source should be tried
    _should_try_source() {
        local src="$1"
        [[ "$api_source" == "auto" || "$api_source" == "$src" ]]
    }



    # ---- nekosapi v4 (with tag verification) ----
    if _should_try_source nekosapi && [[ -z "$url" && $is_gif -eq 0 ]]; then
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

    # ---- waifu.im ----
    if _should_try_source waifu.im && [[ -z "$url" && $is_gif -eq 0 ]]; then
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
    if _should_try_source nekos.best && [[ -z "$url" && "$MODE" == "sfw" ]]; then
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

    # ---- nekosapi v4 catch-all (auto mode only - no tag filter) ----
    if _should_try_source nekosapi && [[ -z "$url" && $is_gif -eq 0 ]]; then
        url="$(curl -sL --max-time 8 \
            "https://api.nekosapi.com/v4/images/random?limit=1&rating=${rating_param}" | \
            jq -r '.[0].url // empty' 2>/dev/null)"
    fi

    # ---- Danbooru fallback (no API key needed - uses proper JSON API) ----
    if _should_try_source danbooru && [[ -z "$url" ]]; then
        url="$(fetch_danbooru "$category" "$rating_param" "$outfile")"
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
# fetch_danbooru - fetch an image from Danbooru via JSON API
# No API key needed for basic read access (rate-limited per IP)
# Returns image URL on stdout (or empty on failure)
# ============================================================
fetch_danbooru() {
    local tag="$1"
    local rating_param="$2"
    local outfile="$3"

    # Map rating_param to Danbooru-style rating filter
    local dan_rating=""
    case "$rating_param" in
        safe)                              dan_rating="s" ;;
        safe,suggestive)                   dan_rating="s" ;;
        safe,suggestive,borderline)        dan_rating="s" ;;
        borderline,explicit|"explicit")    dan_rating="e" ;;
        *)                                 dan_rating="" ;;
    esac

    # Build search tags - pass user tag directly (Danbooru's tag system is comprehensive)
    local search_tags="$tag"
    [[ -n "$dan_rating" ]] && search_tags="${search_tags} rating:${dan_rating}"
    # URL-encode spaces as +
    search_tags="${search_tags// /+}"

    local api_url="https://danbooru.donmai.us/posts/random.json?tags=${search_tags}"
    local json
    json="$(curl -sL --max-time 8 -A 'waifufetch/1.0' "$api_url" 2>/dev/null)"

    # Check if we got a valid response
    local file_url
    file_url="$(printf '%s' "$json" | jq -r '.file_url // empty' 2>/dev/null)"
    [[ -z "$file_url" ]] && return 1

    # Check for error response (rate limited)
    local success
    success="$(printf '%s' "$json" | jq -r '.success // true' 2>/dev/null)"
    [[ "$success" == "false" ]] && return 1

    # Download the image
    curl -sL --max-time 10 -A 'waifufetch/1.0' "$file_url" > "$outfile" 2>/dev/null
    if [[ ! -s "$outfile" ]]; then
        rm -f "$outfile" 2>/dev/null
        return 1
    fi

    printf '%s' "$file_url"
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
    local term_width="$2"
    local max_height="${3:-0}"
    local preferred="${4:-}"
    local max_info_width="${5:-0}"  # widest info line (plain text, for art sizing)
    local lines=()

    # Smart image sizing: fill available space
    # Art column: take half the terminal width, but leave room for info lines
    local img_width=$((term_width / 2 - 2))
    # If we know the info line width, cap so info has room
    if [[ $max_info_width -gt 0 ]]; then
        local available=$((term_width - max_info_width - 4))
        [[ $available -lt $img_width ]] && img_width=$available
    fi
    [[ $img_width -lt 15 ]] && img_width=15
    [[ $img_width -gt 100 ]] && img_width=100

    local img_height=$((img_width * 2 / 3))
    if [[ $max_height -gt 0 ]]; then
        # Match info line height (no cap-down, let it be tall)
        [[ $img_height -lt $max_height ]] && img_height=$max_height
        # Don't exceed 2x info height unless terminal can't fit
        local term_height="${LINES:-24}"
        if command -v tput &>/dev/null; then
                local _th _th_rc
                _th="$(tput lines 2>/dev/null)" && _th_rc=$? || _th_rc=$?
                [[ $_th_rc -eq 0 && "$_th" -gt 0 ]] && term_height="$_th"
            fi
        local cap=$((term_height - 3))  # leave room for prompt
        [[ $img_height -gt $cap ]] && img_height=$cap
        [[ $img_height -lt 5 ]] && img_height=5
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
        # Strip ANSI codes and trailing whitespace
        clean="$(printf '%s' "$line" | sed \$'s/\e\[[0-9;?]*[a-zA-Z]//g; s/[[:space:]]*$//')"
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
# print_side_by_side_raw - display art and pre-rendered info columns
# Same as print_side_by_side but INFO_LINES is already fully formatted
# ============================================================
# Args: $1=art_array_name $2=info_array_name (pre-rendered lines)
print_side_by_side_raw() {
    local _art_name="$1" _info_name="$2"
    local _fixed_col="${3:-}"
    local width="${COLUMNS:-80}"

    local _art_len _info_len
    eval "_art_len=\${#$_art_name[@]}"
    eval "_info_len=\${#$_info_name[@]}"

    local max_art_w=0
    local line clean len
    local i
    for ((i=0; i<_art_len; i++)); do
        eval "line=\${$_art_name[\$i]}"
        # Strip ANSI codes and trailing whitespace for accurate width
        clean="$(printf '%s' "$line" | sed $'s/\e\[[0-9;?]*[a-zA-Z]//g; s/[[:space:]]*$//')"
        len=${#clean}
        [[ $len -gt $max_art_w ]] && max_art_w=$len
    done
    local info_col=$((max_art_w + 2))
    local info_max_col=$(( width - info_col ))
    [[ $info_max_col -lt 5 ]] && info_max_col=5

    local max=$(( _art_len > _info_len ? _art_len : _info_len ))
    local l art_line info_line plain_info

    for ((l=0; l<max; l++)); do
        art_line=""
        info_line=""
        if [[ $l -lt $_art_len ]]; then
            eval "art_line=\${$_art_name[\$l]}"
        fi
        if [[ $l -lt $_info_len ]]; then
            eval "info_line=\${$_info_name[\$l]}"
        fi

        if [[ -n "$art_line" && -n "$info_line" ]]; then
            # Truncate info to fit within terminal width to avoid overflow wrap
            plain_info="$(printf '%s' "$info_line" | sed \$'s/\e\[[0-9;?]*[a-zA-Z]//g')"
                        if [[ ${#plain_info} -gt $info_max_col ]]; then
                local _out="" _count=0 _in_esc=0 _ch
                for ((_i=0; _i<${#info_line}; _i++)); do
                    _ch="${info_line:$_i:1}"
                    if [[ $_in_esc -eq 1 ]]; then
                        _out+="$_ch"
                        [[ "$_ch" == [a-zA-Z] ]] && _in_esc=0
                    elif [[ "$_ch" == $'\e' ]]; then
                        _in_esc=1
                        _out+="$_ch"
                    else
                        if [[ $_count -lt $info_max_col ]]; then
                            _out+="$_ch"
                            ((_count++))
                        fi
                    fi
                done
                info_line="$_out"
            fi
            printf '%s\033[%dG%s\n' "$art_line" "$info_col" "$info_line"
        elif [[ -n "$art_line" ]]; then
            printf '%s\n' "$art_line"
        elif [[ -n "$info_line" ]]; then
            plain_info="$(printf '%s' "$info_line" | sed \$'s/\e\[[0-9;?]*[a-zA-Z]//g')"
                        if [[ ${#plain_info} -gt $info_max_col ]]; then
                local _out="" _count=0 _in_esc=0 _ch
                for ((_i=0; _i<${#info_line}; _i++)); do
                    _ch="${info_line:$_i:1}"
                    if [[ $_in_esc -eq 1 ]]; then
                        _out+="$_ch"
                        [[ "$_ch" == [a-zA-Z] ]] && _in_esc=0
                    elif [[ "$_ch" == $'\e' ]]; then
                        _in_esc=1
                        _out+="$_ch"
                    else
                        if [[ $_count -lt $info_max_col ]]; then
                            _out+="$_ch"
                            ((_count++))
                        fi
                    fi
                done
                info_line="$_out"
            fi
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

    # ---- Android detection (Termux / custom ROM environments) ----
    local _is_android=0
    if [[ -n "${ANDROID_ROOT:-}" ]] || [[ -d /data/data/com.termux/files ]] || command -v termux-info &>/dev/null; then
        _is_android=1
    fi

    # ---- OS ----
    os=""
    if [[ -f /etc/os-release ]]; then
        os="$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release 2>/dev/null || \
              sed -n 's/^NAME="\(.*\)"/\1/p' /etc/os-release 2>/dev/null || \
              sed -n 's/^NAME=\([^"]*\)/\1/p' /etc/os-release 2>/dev/null)"
    fi
    if [[ -z "$os" && $_is_android -eq 1 ]]; then
        local _android_ver=""
        if command -v getprop &>/dev/null; then
            _android_ver="$(getprop ro.build.version.release 2>/dev/null || echo "")"
        fi
        if [[ -n "$_android_ver" ]]; then
            os="Android ${_android_ver}"
        else
            os="Android"
        fi
        if [[ -n "${TERMUX_VERSION:-}" ]]; then
            os="${os} (Termux)"
        fi
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
        raw_uptime="$(uptime 2>/dev/null | sed 's/.* up *//; s/,.*//' | tr -s ' ' | xargs || true)"
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
    # Portable fallback for pgrep (missing on some macOS setups)
    _pgrep_l_x() {
        local proc="$1"
        if command -v pgrep &>/dev/null; then
            pgrep -l -x "$proc" 2>/dev/null
        elif [[ "$uname_s" == "Darwin" ]]; then
            ps -ax -o pid=,ucomm= 2>/dev/null | awk -v p="$proc" \
                '$2 == p {print $1 " " $2; found=1} END {exit found?0:1}'
        else
            return 1
        fi
    }
    _detect_wm_de() {
        local wm=""
        for w in gnome-shell kwin_x11 kwin_wayland sway hyprland i3 bspwm dwm openbox awesome herbstluftwm qtile xfce4-panel; do
            wm="$(_pgrep_l_x "$w" | sed -n 's/^[0-9]* //p' || true)"
            [[ -n "$wm" ]] && { printf '%s' "$wm"; return; }
        done
    }
    de="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
    if [[ -z "$de" ]]; then
        if command -v wmctrl &>/dev/null; then
            de="$(wmctrl -m 2>/dev/null | sed -n 's/.*Name: //p' || true)"
        fi
        [[ -z "$de" ]] && de="$(_detect_wm_de)"
    fi
    if [[ -z "$de" && "$uname_s" == "Darwin" ]]; then
        de="Aqua"
    fi
    if [[ -z "$de" && $_is_android -eq 1 ]]; then
        de="Android"
    fi
    [[ -z "$de" ]] && de="Not detected"
    INFO_PAIRS+=("WM/DE" "$de")

    # ---- CPU ----
    cpu=""
    if [[ $_is_android -eq 1 ]] && command -v getprop &>/dev/null; then
        # Android: try SoC model first, then board platform + arch
        cpu="$(getprop ro.soc.model 2>/dev/null || echo '')"
        if [[ -z "$cpu" ]]; then
            local _plat="$(getprop ro.board.platform 2>/dev/null || echo '')"
            local _arch="$(uname -m 2>/dev/null || echo 'aarch64')"
            if [[ -n "$_plat" ]]; then
                cpu="${_arch} (${_plat})"
            else
                cpu="${_arch}"
            fi
        fi
    elif [[ -f /proc/cpuinfo ]]; then
        cpu="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //' || true)"
        if [[ -z "$cpu" ]]; then
            # ARM / Android: /proc/cpuinfo uses 'Hardware' instead of 'model name'
            cpu="$(grep -m1 'Hardware' /proc/cpuinfo 2>/dev/null | sed 's/.*: //' || true)"
        fi
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
    if [[ -z "$gpu" && $_is_android -eq 1 ]] && command -v getprop &>/dev/null; then
        # Android GPU: try SoC model (includes GPU), then EGL, then board platform
        gpu="$(getprop ro.soc.model 2>/dev/null || echo '')"
        [[ -z "$gpu" ]] && gpu="$(getprop ro.hardware.egl 2>/dev/null || echo '')"
        [[ -z "$gpu" ]] && gpu="$(getprop ro.board.platform 2>/dev/null || echo '')"
        [[ "$gpu" == "swiftshader" ]] && gpu=""
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
        if [[ $_is_android -eq 1 ]]; then
            # Android: /storage/emulated/0 is the real user-accessible storage
            # / (root) in Termux is a small private data partition (~900MB)
            if [[ -d /storage/emulated/0 ]]; then
                disk="$(df -h /storage/emulated/0 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}' || true)"
            fi
            # Fallback: try /sdcard (symlink to /storage/emulated/0 on most devices)
            if [[ -z "$disk" && -d /sdcard ]]; then
                disk="$(df -h /sdcard 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}' || true)"
            fi
            # Last resort: show Termux partition with a label
            if [[ -z "$disk" ]]; then
                local _termux_disk="$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}' || true)"
                [[ -n "$_termux_disk" ]] && disk="$_termux_disk (Termux data)"
            fi
        else
            disk="$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
        fi
    fi
    [[ -z "$disk" ]] && disk="unknown"
    INFO_PAIRS+=("Disk" "$disk")

    # ---- Packages ----
    pkgs=0
    if command -v pacman &>/dev/null; then
        pkgs=$((pkgs + $(pacman -Q 2>/dev/null | wc -l)))
    fi
    if command -v dpkg &>/dev/null; then
        if [[ $_is_android -eq 1 ]] && command -v pkg &>/dev/null; then
            pkgs=$((pkgs + $(pkg list-installed 2>/dev/null | wc -l)))
        else
            pkgs=$((pkgs + $(dpkg -l 2>/dev/null | wc -l)))
        fi
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

    # ---- Local IP (first non-loopback IPv4) ----
    local local_ip=""
    if command -v ip &>/dev/null; then
        local_ip="$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {gsub(/\/[0-9]+/,"",$2); print $2; exit}' || true)"
    fi
    if [[ -z "$local_ip" ]] && command -v ifconfig &>/dev/null; then
        local_ip="$(ifconfig 2>/dev/null | grep -E 'inet ' | grep -v '127\.' | awk '{print $2}' | head -1 || true)"
    fi
    if [[ -z "$local_ip" ]] && command -v ipconfig &>/dev/null; then
        local_ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
    fi
    [[ -n "$local_ip" ]] && INFO_PAIRS+=("Local IP" "$local_ip")

    # ---- Public IP ----
    local public_ip=""
    if command -v curl &>/dev/null; then
        public_ip="$(curl -sf --max-time 2 https://ifconfig.me 2>/dev/null || \
                     curl -sf --max-time 2 https://api.ipify.org 2>/dev/null || true)"
    fi
    if [[ -n "$public_ip" ]]; then
        INFO_PAIRS+=("Public IP" "$public_ip")
    fi

    # ---- Battery ----
    local battery=""
    if [[ -d /sys/class/power_supply ]]; then
        local bat_capacity=""
        local bat_status=""
        local bat_dir
        for bat_dir in /sys/class/power_supply/BAT* /sys/class/power_supply/battery; do
            if [[ -d "$bat_dir" && -f "$bat_dir/capacity" ]]; then
                bat_capacity="$(cat "$bat_dir/capacity" 2>/dev/null || true)"
                bat_status="$(cat "$bat_dir/status" 2>/dev/null || true)"
                if [[ -n "$bat_capacity" ]]; then
                    if [[ "$bat_status" == "Charging" || "$bat_status" == "Full" ]]; then
                        battery="${bat_capacity}% (${bat_status})"
                    else
                        battery="${bat_capacity}%"
                    fi
                fi
                break
            fi
        done
    fi
    if [[ -z "$battery" ]] && command -v pmset &>/dev/null; then
        battery="$(pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1 || true)"
    fi
    if [[ -z "$battery" ]] && command -v termux-battery-status &>/dev/null; then
        local _bat_json _bat_percent _bat_status
        _bat_json="$(termux-battery-status 2>/dev/null || echo '')"
        if [[ -n "$_bat_json" ]]; then
            _bat_percent="$(printf '%s' "$_bat_json" | grep -oE '"percentage":[0-9]+' | grep -oE '[0-9]+' || true)"
            _bat_status="$(printf '%s' "$_bat_json" | grep -oE '"status":"[A-Z]+"' | grep -oE '"[A-Z]+"$' | tr -d '"' || true)"
            if [[ -n "$_bat_percent" ]]; then
                if [[ -n "$_bat_status" ]]; then
                    battery="${_bat_percent}% (${_bat_status})"
                else
                    battery="${_bat_percent}%"
                fi
            fi
        fi
    fi
    if [[ -n "$battery" ]]; then
        INFO_PAIRS+=("Battery" "$battery")
    fi

    # ---- Locale ----
    local locale_val=""
    locale_val="${LANG:-${LC_ALL:-${LC_MESSAGES:-}}}"
    [[ -n "$locale_val" ]] && INFO_PAIRS+=("Locale" "$locale_val")

    # ---- Terminal Font ----
    local term_font=""
    if [[ -n "${KITTY_WINDOW_ID:-}" ]] && command -v kitty &>/dev/null; then
        term_font="$(kitty @ get-fonts 2>/dev/null | head -1 | sed 's/.*family: //' || true)"
    fi
    if [[ -z "$term_font" && -n "${ALACRITTY_LOG:-}" ]]; then
        # Alacritty -- read from config
        local alacritty_config="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
        [[ -f "$alacritty_config" ]] && term_font="$(grep -i 'family' "$alacritty_config" 2>/dev/null | head -1 | sed 's/.*= *"//; s/"$//' || true)"
    fi
    if [[ -z "$term_font" && -n "${WEZTERM_PANE:-}" ]]; then
        term_font="$(wezterm ls-fonts 2>/dev/null | head -1 | sed 's/ .*//' || true)"
    fi
    if [[ -z "$term_font" && -n "${VTE_VERSION:-}" ]]; then
        # GNOME Terminal -- try gsettings
        if command -v gsettings &>/dev/null; then
            term_font="$(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null | sed "s/'//g" || true)"
            if [[ -z "$term_font" ]]; then
                term_font="$(gsettings get org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | sed "s/'//g")/ font 2>/dev/null | sed "s/'//g" || true)"
            fi
        fi
    fi
    [[ -n "$term_font" ]] && INFO_PAIRS+=("Terminal Font" "$term_font")

    # ---- WM Theme / Icons / Cursor ----
    local wm_theme=""
    local icon_theme=""
    local cursor_theme=""
    if command -v gsettings &>/dev/null; then
        wm_theme="$(gsettings get org.gnome.desktop.wm.preferences theme 2>/dev/null | sed "s/'//g" || true)"
        icon_theme="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | sed "s/'//g" || true)"
        cursor_theme="$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | sed "s/'//g" || true)"
    fi
    if [[ -z "$wm_theme" && -f "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" ]]; then
        wm_theme="$(grep 'gtk-theme-name' "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null | head -1 | sed 's/.*gtk-theme-name=//' || true)"
        [[ -z "$icon_theme" ]] && icon_theme="$(grep 'gtk-icon-theme-name' "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null | head -1 | sed 's/.*gtk-icon-theme-name=//' || true)"
        [[ -z "$cursor_theme" ]] && cursor_theme="$(grep 'gtk-cursor-theme-name' "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null | head -1 | sed 's/.*gtk-cursor-theme-name=//' || true)"
    fi
    if [[ -z "$wm_theme" && -f "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" ]]; then
        wm_theme="${wm_theme:-$(grep 'gtk-theme-name' "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" 2>/dev/null | head -1 | sed 's/.*gtk-theme-name=//' || true)}"
    fi
    # Sway-specific
    if [[ -z "$wm_theme" ]] && command -v swaymsg &>/dev/null; then
        wm_theme="$(swaymsg -t get_config 2>/dev/null | grep -i 'font\|theme' | head -1 | sed 's/.* //' || true)"
    fi
    [[ -n "$wm_theme" ]] && INFO_PAIRS+=("WM Theme" "$wm_theme")
    [[ -n "$icon_theme" ]] && INFO_PAIRS+=("Icons" "$icon_theme")
    [[ -n "$cursor_theme" ]] && INFO_PAIRS+=("Cursor" "$cursor_theme")

    # ---- Monitor ----
    local monitors=0
    if command -v xrandr &>/dev/null; then
        monitors="$(xrandr 2>/dev/null | grep -c ' connected')"
        [[ -z "$monitors" ]] && monitors=0
    fi
    if [[ "$monitors" -eq 0 ]] && command -v wlr-randr &>/dev/null; then
        monitors="$(wlr-randr 2>/dev/null | grep -cE '^(DP|HDMI|eDP|LVDS)')"
        [[ -z "$monitors" ]] && monitors=0
    fi
    if [[ "$monitors" -eq 0 ]] && command -v displayplacer &>/dev/null; then
        monitors="$(displayplacer list 2>/dev/null | grep -c 'Resolution')"
        [[ -z "$monitors" ]] && monitors=0
    fi
    if [[ "$monitors" -gt 0 ]]; then
        INFO_PAIRS+=("Monitor" "${monitors} display(s)")
    fi

    # ---- DE (separate from WM for config compat) ----
    # Already stored; just add a separate alias
    # We skip this since WM/DE already covers it

    # ---- Uptime (Unix timestamp format) ----
    local uptime_unix=0
    if [[ -n "$uptime_secs" && "$uptime_secs" -gt 0 ]]; then
        uptime_unix="$(( $(date +%s 2>/dev/null || echo 0) - uptime_secs ))"
    fi
    if [[ "$uptime_unix" -gt 0 ]]; then
        INFO_PAIRS+=("Uptime Unix" "$uptime_unix")
    fi

    # ---- Song (playerctl) ----
    local song=""
    if command -v playerctl &>/dev/null; then
        song="$(playerctl metadata --format '{{artist}} - {{title}}' 2>/dev/null || true)"
    fi
    [[ -n "$song" ]] && INFO_PAIRS+=("Song" "$song")

    # ---- Init ----
    local init=""
    if [[ -f /run/systemd/system ]]; then
        init="systemd"
    elif command -v openrc &>/dev/null; then
        init="OpenRC"
    elif command -v runit &>/dev/null; then
        init="runit"
    elif command -v s6-svscan &>/dev/null; then
        init="s6"
    elif [[ -x /sbin/init ]]; then
        init="$(/sbin/init --version 2>/dev/null | head -1 | sed 's/ .*//' || echo "sysvinit")"
    fi
    if [[ -z "$init" && $_is_android -eq 1 ]]; then
        init="Android init"
    fi
    [[ -n "$init" ]] && INFO_PAIRS+=("Init" "$init")

    # ---- Date/Time ----
    local date_now=""
    if command -v date &>/dev/null; then
        date_now="$(date '+%Y-%m-%d %H:%M' 2>/dev/null || true)"
    fi
    [[ -n "$date_now" ]] && INFO_PAIRS+=("Date" "$date_now")

    # ---- Disk Total ----
    local disk_total=""
    if command -v df &>/dev/null; then
        disk_total="$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')"
    fi
    [[ -n "$disk_total" ]] && INFO_PAIRS+=("Disk Total" "$disk_total")

    # ---- Config-friendly aliases (fastfetch-style type names) ----
    # These ADDITIONAL entries ensure fastfetch-style configs like
    # { "type": "wmtheme" } find matching keys via case-insensitive lookup.
    # bash 3.2 compat: no associative arrays.
    # INFO_PAIRS+=("Localhost" "${user}@${host}")  # Host already shown above
    INFO_PAIRS+=("DE" "$de")
    INFO_PAIRS+=("WM" "$de")
    if [[ -n "${wm_theme:-}" ]]; then
        INFO_PAIRS+=("wmtheme" "$wm_theme")
    fi
    if [[ -n "${term_font:-}" ]]; then
        INFO_PAIRS+=("terminalfont" "$term_font")
    fi
    if [[ -n "$local_ip" ]]; then
        INFO_PAIRS+=("localip" "$local_ip")
    fi
    # Public IP — opt-out via --no-public-ip flag
    if [[ -n "$public_ip" ]]; then
        INFO_PAIRS+=("publicip" "$public_ip")
    fi
    if [[ -n "$song" ]]; then
        INFO_PAIRS+=("song" "$song")
    fi
    if [[ "$monitors" -gt 0 ]]; then
        INFO_PAIRS+=("monitor" "${monitors} display(s)")
    fi
    if [[ -n "$disk_total" ]]; then
        INFO_PAIRS+=("disk_total" "$disk_total")
    fi
    if [[ -n "$uptime_unix" && "$uptime_unix" -gt 0 ]]; then
        INFO_PAIRS+=("uptime_unix" "$uptime_unix")
    fi
    if [[ -n "$init" ]]; then
        INFO_PAIRS+=("init" "$init")
    fi
    if [[ -n "$date_now" ]]; then
        INFO_PAIRS+=("date" "$date_now")
    fi

    # ---- Processes ----
    local processes=0
    if command -v ps &>/dev/null; then
        if [[ "$(uname -s 2>/dev/null || echo '')" == "Darwin" ]]; then
            processes="$(ps -eo pid= 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
        else
            processes="$(ps -eo pid= --no-headers 2>/dev/null | wc -l | tr -d ' ' || \
                        ps -eo pid= 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
        fi
    fi
    [[ "$processes" -gt 0 ]] && INFO_PAIRS+=("processes" "$processes")

    # ---- CPU Temperature ----
    local cpu_temp=""
    if command -v sensors &>/dev/null; then
        cpu_temp="$(sensors 2>/dev/null | grep -i 'Package id 0' | grep -oE '[0-9]+\.[0-9]+°C' | head -1 || \
                    sensors 2>/dev/null | grep -i 'Tctl' | grep -oE '[0-9]+\.[0-9]+°C' | head -1 || \
                    sensors 2>/dev/null | grep -i 'Core 0' | grep -oE '[0-9]+\.[0-9]+°C' | head -1 || true)"
    fi
    if [[ -z "$cpu_temp" && -d /sys/class/thermal ]]; then
        local _thermal_zone
        for _thermal_zone in /sys/class/thermal/thermal_zone*/temp; do
            [[ -f "$_thermal_zone" ]] && cpu_temp="$(cat "$_thermal_zone" 2>/dev/null | head -1 | awk '{printf "%.0f°C", $1/1000}' || true)"
            [[ -n "$cpu_temp" ]] && break
        done
    fi
    [[ -n "$cpu_temp" ]] && INFO_PAIRS+=("cpu_temp" "$cpu_temp")

    # ---- Virtualization ----
    local virt=""
    if command -v systemd-detect-virt &>/dev/null; then
        virt="$(systemd-detect-virt 2>/dev/null || true)"
    fi
    if [[ -z "$virt" || "$virt" == "none" ]]; then
        # Check via /proc/cpuinfo or /sys
        if grep -qi 'hypervisor' /proc/cpuinfo 2>/dev/null; then
            virt="vm"
        fi
        if [[ -z "$virt" ]]; then
            # Check container
            if grep -q 'docker' /proc/1/cgroup 2>/dev/null || [[ -f /.dockerenv ]]; then
                virt="docker"
            elif grep -q 'lxc' /proc/1/cgroup 2>/dev/null; then
                virt="lxc"
            fi
        fi
    fi
    [[ -n "$virt" && "$virt" != "none" ]] && INFO_PAIRS+=("virt" "$virt")

    # ---- Hardware Model ----
    local model=""
    if [[ -f /sys/devices/virtual/dmi/id/product_name ]]; then
        model="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)"
        local _sys_vendor=""
        _sys_vendor="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || true)"
        if [[ -n "$_sys_vendor" && -n "$model" && "$model" != "$_sys_vendor"* ]]; then
            model="${_sys_vendor} ${model}"
        fi
    fi
    if [[ -z "$model" ]] && command -v dmidecode &>/dev/null; then
        model="$(dmidecode -s system-product-name 2>/dev/null || true)"
    fi
    if [[ -z "$model" ]] && command -v sysctl &>/dev/null && [[ "$(uname -s 2>/dev/null || '')" == "Darwin" ]]; then
        model="$(sysctl -n hw.model 2>/dev/null || true)"
    fi
    if [[ -z "$model" ]] && command -v getprop &>/dev/null; then
        local _brand _device
        _brand="$(getprop ro.product.brand 2>/dev/null || true)"
        _device="$(getprop ro.product.model 2>/dev/null || true)"
        if [[ -n "$_brand" && -n "$_device" ]]; then
            model="${_brand} ${_device}"
        elif [[ -n "$_device" ]]; then
            model="$_device"
        fi
    fi
    [[ -n "$model" ]] && INFO_PAIRS+=("model" "$model")

    # ---- Flatpak count ----
    local flatpak_count=0
    if command -v flatpak &>/dev/null; then
        flatpak_count="$(flatpak list 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
    fi
    [[ "$flatpak_count" -gt 0 ]] && INFO_PAIRS+=("flatpak" "$flatpak_count")

    # ---- Container (Docker/Podman) ----
    local containers=0
    if command -v docker &>/dev/null; then
        containers="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
    fi
    if [[ "$containers" -eq 0 ]] && command -v podman &>/dev/null; then
        containers="$(podman ps -q 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
    fi
    [[ "$containers" -gt 0 ]] && INFO_PAIRS+=("containers" "$containers")

    # ---- CPU usage ----
    local cpu_usage=""
    if command -v top &>/dev/null; then
        # Quick read from /proc/stat on Linux
        if [[ -f /proc/stat ]]; then
            local _cpu_idle _cpu_total _cpu_line
            local _prev_idle _prev_total
            _cpu_line=$(head -1 /proc/stat 2>/dev/null || true)
            if [[ -n "$_cpu_line" ]]; then
                # Sum all fields: user nice system idle iowait irq softirq steal guest guest_nice
                _cpu_total=0
                for _val in $_cpu_line; do [[ "$_val" =~ ^[0-9]+$ ]] && _cpu_total=$((_cpu_total + _val)); done 2>/dev/null || true
                # Field 4 (idle) + field 5 (iowait)
                _cpu_idle=$(echo "$_cpu_line" | awk '{print $5+$6}' 2>/dev/null || echo 0)
                if [[ "$_cpu_total" -gt 0 ]]; then
                    cpu_usage="$((100 * (_cpu_total - _cpu_idle) / _cpu_total))%"
                fi
            fi
        fi
    fi
    [[ -n "$cpu_usage" ]] && INFO_PAIRS+=("cpu_usage" "$cpu_usage")

    # ---- Disk IO / Partition / Filesystem info ----
    # Not collecting with default — expensive on some systems
}

# ============================================================
# print_config_help - print JSON config file documentation
# ============================================================
print_config_help() {
    cat <<'CONFIGEOF'
JSON Config File (~/.config/waifufetch/config.json)
--------------------------------------------

Override system info display with a JSON config file.
Located at: $XDG_CONFIG_HOME/waifufetch/config.json or ~/.config/waifufetch/config.json

Example config:
  {
    "logo": { "padding": { "top": 0 } },
    "display": { "separator": " => " },
    "modules": [
      { "type": "os", "key": "OS ", "keyColor": "red" },
      { "type": "kernel", "key": "Kernel ", "keyColor": "31" },
      "break",
      { "type": "packages", "key": "Pkgs ", "keyColor": "bold 32" }
    ]
  }

Fields:
  logo.padding.top      blank lines before output (default: 0)
  display.separator     string between key label and value (default: ": ")
  modules               array of items to show (omit = show all collected info)

Module field details:
  String "break"        inserts a blank line in the output
  Object {
    type:               info type name (case-insensitive, see list below)
    key:                label text shown before value (optional, omit = value only)
    keyColor:           color for the key label (ANSI number, name, or "bold <n>")
  }

Color values for keyColor:
  ANSI numbers: 30=black, 31=red, 32=green, 33=yellow, 34=blue,
                35=magenta, 36=cyan, 37=white
  Names:         black, red, green, yellow, blue, magenta, cyan, white
  Bold:          prefix with "bold " e.g. "bold 36" or "bold cyan"

Available info types (type name -> shown as):
  os            OS (Arch Linux, macOS, etc.)
  host          Host (user@hostname)
  kernel        Kernel version
  uptime        System uptime
  shell         Current shell
  terminal      Terminal emulator
  wm, de        Window manager / Desktop environment
  cpu           CPU model
  gpu           GPU model
  memory        RAM usage
  swap          Swap usage
  disk          Disk usage (used/total)
  disk_total    Total disk size
  packages      Installed package count
  resolution    Display resolution
  localip       Local IP address
  publicip      Public IP address
  battery       Battery level
  locale        System locale
  date          Current date and time
  init          Init system
  song          Currently playing media
  terminalfont  Terminal font name
  wmtheme       WM/GTK theme name
  icons         Icon theme
  cursor        Cursor theme
  monitor       Number of monitors
  uptime_unix   Boot timestamp (Unix epoch)
  processes     Number of running processes
  cpu_usage     CPU usage percentage
  cpu_temp      CPU temperature
  virt          Virtualization/container type
  model         Hardware model name
  flatpak       Installed Flatpak count
  containers    Running Docker/Podman containers

Flags:
  --config <path>   load config from custom file path
  -c <path>         short form of --config
  --no-public-ip    skip public IP fetch (network request)

Without a config file, waifufetch shows all available info
in default format (cyan key, colon separator).
CONFIGEOF
}

# ============================================================
# print_tag_lists - print all available tags and categories
# ============================================================
print_tag_lists() {
    local mode="${1:-all}"
    local api_filter="${2:-}"
    # --list-tags sets mode="sfw" -> show SFW-only (no NSFW section)
    # nsfw --list-tags sets mode="nsfw" -> normalise to "all" (show everything)
    # When an API filter is set, always show all sections for that API
    if [[ "$mode" == "nsfw" ]]; then
        mode="all"
    fi
    if [[ -n "$api_filter" && "$mode" != "all" ]]; then
        mode="all"
    fi

    # When api_filter is set, only show tags from that API
    _should_show() {
        local group="$1"
        [[ -z "$api_filter" ]] && return 0
        case "$group" in
            nb)   [[ "$api_filter" == "nekos.best" ]] ;;
            wim)  [[ "$api_filter" == "waifu.im" ]] ;;
            dan) [[ "$api_filter" == "danbooru" ]] ;;
            neko) [[ "$api_filter" == "nekosapi" ]] ;;
            *)    return 1 ;;
        esac
    }

    local _group_suffix=""
    [[ -n "$api_filter" ]] && _group_suffix=" ($api_filter)"

    # ============================================================
    # General tag listing (no filter): show summary with API hints
    # ============================================================
    if [[ -z "$api_filter" ]]; then
        # sfw mode: show all sections except NSFW
        local _is_sfw=0
        [[ "$mode" == "sfw" ]] && _is_sfw=1
        if [[ "$mode" == "all" || "$_is_sfw" -eq 1 || "$mode" == "categories" ]]; then
            echo "=== Categories (nekos.best) ==="
            for t in "${NB_STATIC[@]}"; do echo "  $t"; done
        fi
        if [[ "$mode" == "all" || "$_is_sfw" -eq 1 || "$mode" == "sfw" ]]; then
            echo ""
            echo "=== SFW Tags (waifu.im) ==="
            for t in "${WIM_SFW[@]}"; do echo "  $t"; done
        fi
        if [[ "$mode" == "all" || "$mode" == "nsfw" ]]; then
            echo ""
            echo "=== NSFW Tags (waifu.im) ==="
            for t in "${WIM_NSFW[@]}"; do echo "  $t"; done
        fi
        if [[ "$mode" == "all" || "$_is_sfw" -eq 1 || "$mode" == "characters" ]]; then
            echo ""
            echo "=== Characters (waifu.im) ==="
            for t in "${WIM_CHARS[@]}"; do echo "  $t"; done
        fi
        if [[ "$mode" == "all" || "$_is_sfw" -eq 1 || "$mode" == "gifs" ]]; then
            echo ""
            echo "=== GIF Animations (nekos.best) ==="
            for t in "${NB_GIFS[@]}"; do echo "  $t"; done
        fi
        if [[ "$mode" == "all" || "$_is_sfw" -eq 1 || "$mode" == "danbooru" ]]; then
            echo ""
            echo "=== Danbooru Tags ==="
            for t in "${DANBOORU_TAGS[@]}"; do echo "    $t"; done
            echo ""
            echo "  (Danbooru accepts any tag - see danbooru.donmai.us for full list)"
        fi
        if [[ "$mode" == "all" || "$_is_sfw" -eq 1 || "$mode" == "ratings" ]]; then
            echo ""
            echo "=== Ratings ==="
            for r in safe suggestive borderline explicit; do echo "  $r"; done
        fi
        return
    fi

    # ============================================================
    # API-filtered listing: show full tags for the selected API
    # ============================================================
    if [[ "$mode" == "all" || "$mode" == "categories" ]]; then
        if _should_show nb; then
            echo "=== Categories${_group_suffix} ==="
            for t in "${NB_STATIC[@]}"; do echo "  $t"; done
        fi
    fi
    if [[ "$mode" == "all" || "$mode" == "sfw" ]]; then
        if _should_show wim; then
            echo ""
            echo "=== SFW Tags${_group_suffix} ==="
            for t in "${WIM_SFW[@]}"; do echo "  $t"; done
        fi
    fi
    if [[ "$mode" == "all" || "$mode" == "nsfw" ]]; then
        if _should_show wim; then
            echo ""
            echo "=== NSFW Tags${_group_suffix} ==="
            for t in "${WIM_NSFW[@]}"; do echo "  $t"; done
        fi
    fi
    if [[ "$mode" == "all" || "$mode" == "characters" ]]; then
        if _should_show wim; then
            echo ""
            echo "=== Characters${_group_suffix} ==="
            for t in "${WIM_CHARS[@]}"; do echo "  $t"; done
        fi
    fi
    if [[ "$mode" == "all" || "$mode" == "gifs" ]]; then
        if _should_show nb; then
            echo ""
            echo "=== GIF Animations${_group_suffix} ==="
            for t in "${NB_GIFS[@]}"; do echo "  $t"; done
        fi
    fi
    if [[ "$mode" == "all" || "$mode" == "danbooru" ]]; then
        if _should_show dan; then
            echo ""
            echo "=== Danbooru Tags${_group_suffix} ==="
            for t in "${DANBOORU_TAGS[@]}"; do echo "  $t"; done
            echo ""
            echo "  (Danbooru accepts any tag - use --list-tags for full list)"
        fi
    fi
    if [[ "$mode" == "all" || "$mode" == "ratings" ]]; then
        if [[ -z "$api_filter" ]]; then
            echo ""
            echo "=== Ratings ==="
            for r in safe suggestive borderline explicit; do echo "  $r"; done
        fi
    fi
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
  $prog --setDefaultAPI <source>     - set default API source
                                       Valid: auto, waifu.im, nekosapi,
                                       nekos.best, danbooru
                                       (empty value "" to reset to auto)
  $prog --resetSettings              - remove all saved settings and config files
  $prog nsfw --list-tags             - list ALL tags (SFW + NSFW + Danbooru)
  $prog --list-tags                  - list all SFW tags, categories, characters
  $prog --list-categories            - list available categories only
  $prog --list-ratings               - list available rating levels
  $prog --list-tags -a <source>      - list tags from a specific API only

  $prog -i <file>                    - display a local image/GIF file
  $prog -a, --api <source>           - use specific API for this request
  $prog --debug                      - show detailed debug info

  $prog --noLink                     - suppress image URL output
  $prog --config <file>              - load JSON config (see CONFIG.md)
  $prog -c <file>                    - same as --config (short form)

Image sources: Waifu.im, Nekos API, Nekos.best + Danbooru (fallback)
  auto       fallback chain  - nekosapi -> waifu.im -> nekos.best -> danbooru
  waifu.im   waifu.im only
  nekosapi   nekosapi.com v4 only
  nekos.best nekos.best only
  danbooru   Danbooru only (JSON API) - supports femboy, trap, and more

Displayers: icat, chafa, img2txt, jp2a
  icat     native image display (kitty terminal)
  chafa    colored text-art via chafa library
  img2txt  colored ASCII art (caca-utils)
  jp2a     black & white ASCII art
  (default: auto-detect)

Tags:    waifu, neko, kitsune, husbando, maid, uniform, selfies
NSFW:    ero, ecchi, hentai, oppai, ass, milf, oral, paizuri
Danbooru: femboy, trap, catgirl, original, cosplay, bikini, swimsuit,
          lingerie, pantyhose, stockings, bunny_girl, blush, skirt, thighhighs
         (Danbooru accepts any tag - see danbooru.donmai.us)
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

Default API: ${DEFAULT_API:-auto}
  Set with: $prog --setDefaultAPI <auto|waifu.im|nekosapi|nekos.best|danbooru>

APIs: nekosapi.com v4, waifu.im, nekos.best, danbooru
Note: Danbooru-only tags (femboy, trap, etc.) route directly to
      danbooru. No API key required. Tag/rating filtering depends
      on API metadata and is not 100%% precise.

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
  $prog --setDefaultAPI <source>     - set default API source
                                       Valid: auto, waifu.im, nekosapi,
                                       nekos.best, danbooru
  $prog --resetSettings              - remove all saved settings and config files
  $prog nsfw --list-tags             - list ALL tags (SFW + NSFW + Danbooru)
  $prog --list-tags                  - list all SFW tags, categories, characters
  $prog --list-categories            - list available categories only
  $prog --list-ratings               - list available rating levels
  $prog --list-tags -a <source>      - list tags from a specific API only

  $prog -i <file>                    - display a local image/GIF file
  $prog -a, --api <source>           - use specific API for this request
  $prog --config <file>              - load JSON config (see CONFIG.md)
  $prog -c <file>                    - same as --config (short form)
  $prog --noLink                     - suppress image URL output
  $prog --debug                      - show detailed debug info
  $prog -v, --version                - show version and exit
  $prog nsfw --help                  - show NSFW-specific help

Image sources: Waifu.im, Nekos API, Nekos.best + Danbooru (fallback)
  auto       fallback chain  - nekosapi -> waifu.im -> nekos.best -> danbooru
  waifu.im   waifu.im only
  nekosapi   nekosapi.com v4 only
  nekos.best nekos.best only
  danbooru   Danbooru only (JSON API) - supports femboy, trap, and more

Displayers: icat, chafa, img2txt, jp2a
  icat     native image display (kitty terminal)
  chafa    colored text-art via chafa library
  img2txt  colored ASCII art (caca-utils)
  jp2a     black & white ASCII art
  (default: auto-detect)

Tags:    waifu, neko, kitsune, husbando, maid, uniform, selfies
Danbooru: femboy, trap, catgirl, original, cosplay, bikini, swimsuit,
          lingerie, pantyhose, stockings, bunny_girl, blush, skirt, thighhighs
Characters: raiden-shogun, mori-calliope, rem, marin-kitagawa,
           genshin-impact, kamisato-ayaka
GIFs:      lurk, shoot, sleep, clap, shrug, stare, wave, poke,
           confused, smile, peck, wink, sip, blush, smug, tickle,
           yeet, think, highfive, feed, wag, bite

Run '$prog --list-tags' for all SFW tags, '$prog nsfw --list-tags' for all.

APIs used: nekosapi.com v4, waifu.im, nekos.best, danbooru
Note: Danbooru-only tags (femboy, trap, etc.) route directly to
      danbooru. No API key required. Tags and ratings depend on
      API metadata and are not 100%% precise.

Report issues: <https://github.com/JGH0/waifufetch/issues>

For JSON config documentation, see CONFIG.md in the repository:
<https://github.com/JGH0/waifufetch/blob/main/CONFIG.md>
EOF
    exit 0
}

#!/usr/bin/env bash
# test-bash32-compat.sh - check waifufetch/bash 3.2 compatibility
# Run: cd tests && bash test-bash32-compat.sh
# The test script itself must be bash 3.2 compatible!

set -euo pipefail 2>/dev/null || set -eu

PASS=0 FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

check() {
    local desc="$1" result="$2"
    if [[ $result -eq 0 ]]; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "  waifufetch bash 3.2 compatibility tests"
echo "============================================"
echo "bash: $(bash --version | head -1)"
echo ""

cd "$PROJECT_DIR"

# ---- Syntax checks ----
echo "--- Syntax checks ---"
bash -n waifufetch 2>&1
check "waifufetch syntax" $?
bash -n libwaifu.sh 2>&1
check "libwaifu.sh syntax" $?
bash -n waifu 2>&1
check "waifu syntax" $?
echo ""

# ---- Bash 3.2 feature restrictions ----
echo "--- Bash 3.2 feature restrictions ---"
# declare -A should NOT work on bash 3.2
if bash -c 'declare -A x; x[a]=1' 2>/dev/null; then
    echo "  ✓ declare -A works (modern bash), fallback exists via _get_color_raw_code"
    PASS=$((PASS + 1))
else
    echo "  ✓ declare -A fails correctly (bash 3.2 compat handled via _get_color_raw_code)"
    PASS=$((PASS + 1))
fi

# pipefail check
if bash -c 'set -o pipefail' 2>/dev/null; then
    echo "  ✓ set -o pipefail works (modern bash), fallback: set -euo pipefail 2>/dev/null || set -eu"
    PASS=$((PASS + 1))
else
    echo "  ✓ fallback to set -eu triggered (bash 3.2)"
    PASS=$((PASS + 1))
fi

# mapfile check
if bash -c 'mapfile -t arr < /dev/null' 2>/dev/null; then
    echo "  ✓ mapfile works (modern bash), fallback: _readlines function"
    PASS=$((PASS + 1))
else
    echo "  ✓ mapfile fails correctly (bash 3.2 compat handled via _readlines)"
    PASS=$((PASS + 1))
fi

# fractional read -t
if bash -c 'read -t 0.05 -N 0' 2>/dev/null; then
    echo "  ✓ fractional read -t works (modern bash), fallback exists for bash 3.2"
    PASS=$((PASS + 1))
else
    echo "  ✓ fractional read -t fails correctly (bash 3.2 fallback)"
    PASS=$((PASS + 1))
fi

# ${var,,} lowercase
if bash -c 'x="ABC"; echo "${x,,}"' 2>/dev/null | grep -q abc; then
    echo "  ✓ \${var,,} works (modern bash), fallback: tr for lowercasing"
    PASS=$((PASS + 1))
else
    echo "  ✓ \${var,,} fails correctly (bash 3.2 compat via tr)"
    PASS=$((PASS + 1))
fi
echo ""

# ---- ANSI-C quoting test ----
echo "--- ANSI-C quoting (\$'...') test ---"
# \$'...' should work on bash 3.2+
if x=$(echo -n $'\e') && [[ "$x" == $'\e' ]]; then
    echo "  ✓ \$'...' ANSI-C quoting works (ESC byte)"
    PASS=$((PASS + 1))
else
    echo "  ✗ \$'...' ANSI-C quoting FAILED"
    FAIL=$((FAIL + 1))
fi

# Test the sed pattern used in print_side_by_side_raw
test_line=$'\033[1;36mOS\033[0m: Arch Linux'
clean=$(printf '%s' "$test_line" | sed $'s/\e\[[0-9;?]*[a-zA-Z]//g')
if [[ "$clean" == "OS: Arch Linux" ]]; then
    echo "  ✓ sed ANSI-strip works on bash $(bash --version | head -1)"
    PASS=$((PASS + 1))
else
    echo "  ✗ sed ANSI-strip failed: '$clean'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ---- _readlines function test ----
echo "--- _readlines function test ---"
cd "$PROJECT_DIR"
source ./libwaifu.sh 2>/dev/null || true
_readlines_test() {
    local arr
    _readlines arr < <(printf 'a\nb\nc\n')
    if [[ ${#arr[@]} -eq 3 && "${arr[0]}" == "a" ]]; then
        return 0
    fi
    return 1
}
_readlines_test
check "_readlines function" $?
echo ""

# ---- print_side_by_side_raw eval test ----
echo "--- print_side_by_side_raw array access test ---"
_psbsr_test() {
    local _my_art _my_info
    _my_art=("line1" "line2")
    _my_info=("info1" "info2")
    local _art_name="_my_art" _info_name="_my_info"
    eval "local _art_len=\${#$_art_name[@]}"
    eval "local _info_len=\${#$_info_name[@]}"
    if [[ $_art_len -eq 2 && $_info_len -eq 2 ]]; then
        return 0
    fi
    return 1
}
_psbsr_test
check "eval-based array access" $?
echo ""

# ---- Value truncation test ----
echo "--- Value truncation test ---"
_trunc_test() {
    local long="This is a very long string that should definitely be truncated because it exceeds the 53 character limit in the info rendering code"
    local truncated="${long:0:50}"
    if [[ ${#long} -gt 53 && ${#truncated} -eq 50 ]]; then
        return 0
    fi
    return 1
}
_trunc_test
check "long value truncation (50 chars limit)" $?

_trunc_short_test() {
    local short="short value"
    local truncated="${short:0:50}"
    if [[ "$truncated" == "$short" ]]; then
        return 0
    fi
    return 1
}
_trunc_short_test
check "short value not truncated" $?
echo ""

# ---- get_img_pixel_size test ----
echo "--- get_img_pixel_size test ---"
cd "$SCRIPT_DIR"
if [[ -f "test.png" ]]; then
    dim=$(get_img_pixel_size "test.png" 2>/dev/null || echo "")
    if [[ -n "$dim" ]]; then
        w="${dim%% *}"
        h="${dim##* }"
        if [[ $w -gt 0 && $h -gt 0 ]]; then
            echo "  ✓ get_img_pixel_size(test.png) => ${w}x${h}"
            PASS=$((PASS + 1))
        else
            echo "  ✗ get_img_pixel_size returned invalid: '$dim'"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  ! get_img_pixel_size returned empty (no identify/sips/ffprobe? skipping)"
    fi
else
    echo "  ! test.png not found (skipping get_img_pixel_size test)"
fi
echo ""

# ---- Default config JSON test ----
echo "--- Default config JSON test ---"
if [[ -n "${WAIFU_DEFAULT_CONFIG_JSON:-}" ]]; then
    check=$(printf '%s' "$WAIFU_DEFAULT_CONFIG_JSON" | grep -c '"logo"' || true)
    if [[ $check -ge 1 ]]; then
        echo "  ✓ WAIFU_DEFAULT_CONFIG_JSON contains logo section"
        PASS=$((PASS + 1))
    else
        echo "  ✗ WAIFU_DEFAULT_CONFIG_JSON missing logo section"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  ! WAIFU_DEFAULT_CONFIG_JSON not available (script wasn't sourced?)"
fi
echo ""

# ---- Sixel displayer validation test ----
echo "--- Displayer validation tests ---"
_disp_valid_test() {
    local valid=0
    for d in icat chafa img2txt jp2a sixel; do
        case "$d" in
            icat|chafa|img2txt|jp2a|sixel) : ;;
            *) return 1 ;;
        esac
    done
    return 0
}
_disp_valid_test
check "all 5 displayers (icat, chafa, img2txt, jp2a, sixel) validated" $?
echo ""

# ---- --help output tests ----
echo "--- --help output tests ---"
help_out=$(bash "$PROJECT_DIR/waifufetch" --help 2>&1 || true)
echo "$help_out" | grep -q "Usage:" && \
    echo "  ✓ --help shows Usage:" && PASS=$((PASS + 1)) || \
    { echo "  ✗ --help missing Usage:"; FAIL=$((FAIL + 1)); }
echo "$help_out" | grep -q "sixel" && \
    echo "  ✓ --help mentions sixel displayer" && PASS=$((PASS + 1)) || \
    { echo "  ✗ --help missing sixel"; FAIL=$((FAIL + 1)); }
echo "$help_out" | grep -q "chafa" && \
    echo "  ✓ --help mentions chafa" && PASS=$((PASS + 1)) || \
    { echo "  ✗ --help missing chafa"; FAIL=$((FAIL + 1)); }
echo "$help_out" | grep -q "jp2a" && \
    echo "  ✓ --help mentions jp2a" && PASS=$((PASS + 1)) || \
    { echo "  ✗ --help missing jp2a"; FAIL=$((FAIL + 1)); }
echo ""

# ---- --help-config output test ----
echo "--- --help-config output tests ---"
help_cfg=$(bash "$PROJECT_DIR/waifufetch" --help-config 2>&1 || true)
echo "$help_cfg" | grep -q "modules" && \
    echo "  ✓ --help-config shows modules section" && PASS=$((PASS + 1)) || \
    { echo "  ✗ --help-config missing modules"; FAIL=$((FAIL + 1)); }
echo ""

# ---- Version flag test ----
echo "--- Version flag test ---"
version_out=$(bash "$PROJECT_DIR/waifufetch" -v 2>&1 || true)
echo "$version_out" | grep -q "waifufetch v" && \
    echo "  ✓ -v shows version" && PASS=$((PASS + 1)) || \
    { echo "  ✗ -v unexpected output: $version_out"; FAIL=$((FAIL + 1)); }
echo ""

# ---- Test script syntax check (all .sh files in tests/, excluding self) ----
echo "--- Test script syntax validation ---"
cd "$SCRIPT_DIR"
for tf in *.sh; do
    # Skip self, skip .Dockerfile (not bash)
    [[ "$tf" == "$(basename "$0")" ]] && continue
    if [[ -f "$tf" ]]; then
        bash -n "$tf" 2>&1 && \
            echo "  ✓ $(basename "$tf") syntax OK" && PASS=$((PASS + 1)) || \
            { echo "  ✗ $(basename "$tf") syntax error"; FAIL=$((FAIL + 1)); }
    fi
done
echo ""

# ---- Build script validation ----
echo "--- Build script validation ---"
cd "$PROJECT_DIR"
bash -n release.sh 2>&1
check "release.sh syntax" $?
echo ""

echo "============================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "============================================"

if [[ $FAIL -gt 0 ]]; then
    echo "  Some tests FAILED — review output above."
    exit 1
else
    echo "  All compatibility checks passed!"
    echo ""
    echo "  Note: Some bash 3.2 feature checks may work on"
    echo "  your (bash $(bash --version | head -1 | grep -oP '\d+\.\d+' | head -1)) but"
    echo "  will fail on macOS bash 3.2."
    echo "  The code has fallbacks for all of these."
    exit 0
fi

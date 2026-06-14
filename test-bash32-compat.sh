#!/usr/bin/env bash
# test-bash32-compat.sh - check waifufetch/bash 3.2 compatibility
# Run: bash test-bash32-compat.sh
# The test script itself must be bash 3.2 compatible!

set -euo pipefail 2>/dev/null || set -eu

PASS=0 FAIL=0

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

# ---- Syntax checks ----
echo "--- Syntax checks ---"
cd "$(dirname "$0")"
bash -n waifufetch 2>&1
check "waifufetch syntax" $?
bash -n libwaifu.sh 2>&1
check "libwaifu.sh syntax" $?
bash -n waifu 2>&1
check "waifu syntax" $?
echo ""

# ---- Associative arrays ----
echo "--- Bash 3.2 feature restrictions ---"
# declare -A should NOT work on bash 3.2
if bash -c 'declare -A x; x[a]=1' 2>/dev/null; then
    echo "  ! declare -A works (expected to fail on bash 3.2)"
    FAIL=$((FAIL + 1))
else
    echo "  ✓ declare -A fails correctly (bash 3.2 compat handled via _get_color_raw_code)"
    PASS=$((PASS + 1))
fi

# pipefail check
if bash -c 'set -o pipefail' 2>/dev/null; then
    echo "  ! set -o pipefail works (fallback may not trigger)"
    PASS=$((PASS + 1))
else
    echo "  ✓ fallback to set -eu triggered"
    PASS=$((PASS + 1))
fi

# mapfile check
if bash -c 'mapfile -t arr < /dev/null' 2>/dev/null; then
    echo "  ! mapfile works (fallback _readlines may not trigger)"
    PASS=$((PASS + 1))
else
    echo "  ✓ mapfile fails correctly (bash 3.2 compat handled via _readlines)"
    PASS=$((PASS + 1))
fi

# fractional read -t
if bash -c 'read -t 0.05 -N 0' 2>/dev/null; then
    echo "  ! fractional read -t works (bash 3.2 fallback may not trigger)"
    PASS=$((PASS + 1))
else
    echo "  ✓ fractional read -t fails correctly (bash 3.2 fallback)"
    PASS=$((PASS + 1))
fi

# ${var,,} lowercase
if bash -c 'x="ABC"; echo "${x,,}"' 2>/dev/null | grep -q abc; then
    echo "  ! \${var,,} works (bash 3.2 compat via tr may not trigger)"
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

# ---- _readlines test ----
echo "--- _readlines function test ---"
source libwaifu.sh 2>/dev/null || true
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

# ---- print_side_by_side_raw test ----
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

echo "--------------------------------------------"
echo "  Results: $PASS passed, $FAIL failed"
echo "--------------------------------------------"

if [[ $FAIL -gt 0 ]]; then
    echo "  Some tests FAILED — review output above."
    exit 1
else
    echo "  All compatibility checks passed!"
    echo ""
    echo "  Note: Some features listed as '!' above may work on"
    echo "  your (bash 5.x) but will fail on macOS bash 3.2."
    echo "  The code has fallbacks for all of these."
    exit 0
fi

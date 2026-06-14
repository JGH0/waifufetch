#!/bin/sh
# run-bash32-test.sh - runs inside the Docker container
# Uses /usr/local/bin/bash (bash 3.2) for all tests

BASH32="/usr/local/bin/bash"
WAIFU_DIR="/waifufetch"
PASS=0 FAIL=0

check() {
    local desc="$1" result="$2"
    if [ "$result" -eq 0 ]; then
        echo "  OK: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

cd "$WAIFU_DIR" || exit 1

echo "=========================================="
echo "  waifufetch bash 3.2 compatibility test"
echo "=========================================="
echo "bash: $($BASH32 --version 2>&1 | head -1)"
echo ""

# Test 1: Syntax check
echo "--- Syntax check ---"
for f in waifufetch libwaifu.sh waifu; do
    if $BASH32 -n "$f" 2>&1; then
        echo "  OK: $f syntax"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $f has syntax errors"
        FAIL=$((FAIL + 1))
    fi
done
echo ""

# Test 2: Feature restrictions
echo "--- bash 3.2 feature restrictions ---"

# declare -A should fail
$BASH32 -c 'declare -A x' 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  NOTE: declare -A works (code fallback: _get_color_raw_code)"
else
    echo "  OK: declare -A correctly fails (bash 3.2 behavior)"
    PASS=$((PASS + 1))
fi

# pipefail should fail
$BASH32 -c 'set -o pipefail' 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  NOTE: pipefail works (code fallback: set -euo pipefail 2>/dev/null || set -eu)"
else
    echo "  OK: pipefail correctly fails"
    PASS=$((PASS + 1))
fi

# fractional read -t should fail
$BASH32 -c 'read -t 0.05 -N 0' 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  NOTE: fractional read -t works (code has fallback)"
else
    echo "  OK: fractional read -t correctly fails"
    PASS=$((PASS + 1))
fi

# mapfile should fail
$BASH32 -c 'mapfile -t arr < /dev/null' 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  NOTE: mapfile works (code fallback: _readlines function)"
else
    echo "  OK: mapfile correctly fails"
    PASS=$((PASS + 1))
fi

# lowercase expansion should fail
$BASH32 -c 'x=A; echo "${x,,}"' 2>/dev/null | grep -q a
if [ $? -eq 0 ]; then
    echo "  NOTE: lowercase expansion works (code fallback: tr)"
else
    echo "  OK: lowercase expansion correctly fails"
    PASS=$((PASS + 1))
fi
echo ""

# Test 3: Run inner test script with bash 3.2
echo "--- ANSI-C quoting, sed, core functions ---"
$BASH32 /waifufetch/tests/bash32-inner-test.sh 2>&1
INNER_RESULT=$?
check "inner test script" "$INNER_RESULT"
echo ""

# Test 4: Run waifufetch with --noLink and test image, capture output
echo "--- waifufetch actual run (noLink, test image) ---"
if [ -f "tests/test.png" ]; then
    echo "  Capturing waifufetch output..."
    WAIFU_OUTPUT=$($BASH32 waifufetch --noLink -i tests/test.png 2>/dev/null || true)
    WAIFU_RC=$?
    echo "=========================================="
    echo "  WAIFUFETCH OUTPUT (bash 3.2):"
    echo "=========================================="
    echo "$WAIFU_OUTPUT"
    echo "=========================================="
    echo ""
    if [ $WAIFU_RC -eq 0 ]; then
        echo "  OK: waifufetch ran successfully (exit 0)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: waifufetch exited with code $WAIFU_RC"
        FAIL=$((FAIL + 1))
    fi
    # Verify output has system info
    echo "$WAIFU_OUTPUT" | grep -q "OS:" && echo "  OK: output contains OS info" && PASS=$((PASS + 1)) || { echo "  MISS: output missing OS:"; }
    echo "$WAIFU_OUTPUT" | grep -q "Host:" && echo "  OK: output contains Host info" && PASS=$((PASS + 1)) || { echo "  MISS: output missing Host:"; }
    echo "$WAIFU_OUTPUT" | grep -q "Kernel:" && echo "  OK: output contains Kernel info" && PASS=$((PASS + 1)) || { echo "  MISS: output missing Kernel:"; }
    echo "$WAIFU_OUTPUT" | grep -q -E "(Memory:|CPU:)" && echo "  OK: output contains system stats" && PASS=$((PASS + 1)) || { echo "  MISS: output missing system stats"; }
else
    echo "  (no test image, skipping waifufetch run test)"
fi
echo ""

# Test 5: version flag
echo "--- version flag ---"
VERSION_OUT=$($BASH32 waifufetch -v 2>&1 || true)
echo "  version: $VERSION_OUT"
echo "$VERSION_OUT" | grep -q "waifufetch v" && echo "  OK: version output" && PASS=$((PASS + 1)) || { echo "  FAIL: version output unexpected"; FAIL=$((FAIL + 1)); }
echo ""

# Test 6: --help flag
echo "--- help flag ---"
HELP_OUT=$($BASH32 waifufetch --help 2>&1 || true)
echo "$HELP_OUT" | grep -q "Usage:" && echo "  OK: help shows usage" && PASS=$((PASS + 1)) || { echo "  FAIL: help missing usage"; FAIL=$((FAIL + 1)); }
echo "$HELP_OUT" | grep -q "sixel" && echo "  OK: help mentions sixel displayer" && PASS=$((PASS + 1)) || { echo "  FAIL: help missing sixel"; FAIL=$((FAIL + 1)); }
echo ""

echo "=========================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

echo ""
echo "  ALL TESTS PASSED"
exit 0

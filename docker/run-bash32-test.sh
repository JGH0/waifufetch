#!/bin/sh
# run-bash32-test.sh - runs inside the Docker container
# Uses /usr/local/bin/bash (bash 3.2) for all tests

BASH32="/usr/local/bin/bash"
WAIFU_DIR="/waifufetch"

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
    else
        echo "  FAIL: $f has syntax errors"
        exit 1
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
fi

# pipefail should fail
$BASH32 -c 'set -o pipefail' 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  NOTE: pipefail works (code fallback: set -euo pipefail 2>/dev/null || set -eu)"
else
    echo "  OK: pipefail correctly fails"
fi

# fractional read -t should fail
$BASH32 -c 'read -t 0.05 -N 0' 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  NOTE: fractional read -t works (code has fallback)"
else
    echo "  OK: fractional read -t correctly fails"
fi

# mapfile should fail
$BASH32 -c 'mapfile -t arr < /dev/null' 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  NOTE: mapfile works (code fallback: _readlines function)"
else
    echo "  OK: mapfile correctly fails"
fi

# lowercase expansion should fail
$BASH32 -c 'x=A; echo "${x,,}"' 2>/dev/null | grep -q a
if [ $? -eq 0 ]; then
    echo "  NOTE: lowercase expansion works (code fallback: tr)"
else
    echo "  OK: lowercase expansion correctly fails"
fi
echo ""

# Test 3: Run inner test script with bash 3.2
echo "--- ANSI-C quoting, sed, core functions ---"
$BASH32 /waifufetch/docker/bash32-inner-test.sh 2>&1
INNER_RESULT=$?
echo ""

if [ $INNER_RESULT -eq 0 ]; then
    echo "=========================================="
    echo "  ALL TESTS PASSED"
    echo "=========================================="
else
    echo "=========================================="
    echo "  SOME TESTS FAILED"
    echo "=========================================="
    exit 1
fi

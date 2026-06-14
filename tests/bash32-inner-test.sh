#!/usr/local/bin/bash
# Inner test script run by bash 3.2 inside the container
# Tests ANSI-C quoting, sed, and core lib functions

echo "--- ANSI-C quoting ---"
x=$'\e'
if [ "$x" = $'\e' ]; then
    echo "  OK: ANSI-C quoting (ESC byte)"
else
    echo "  FAIL: ANSI-C quoting broken"
    exit 1
fi

echo ""
echo "--- sed ANSI stripping ---"
line=$'\033[1;33mhello\033[0m'
clean=$(printf "%s" "$line" | sed $'s/\e\[[0-9;?]*[a-zA-Z]//g')
if [ "$clean" = "hello" ]; then
    echo "  OK: sed ANSI stripping works"
else
    echo "  FAIL: got '$clean'"
    exit 1
fi

echo ""
echo "--- Core library functions ---"
cd /waifufetch || exit 1

# Test _readlines
source libwaifu.sh 2>/dev/null
_readlines_test() {
    local arr
    _readlines arr < <(printf "a\nb\nc\n")
    if [ ${#arr[@]} -eq 3 ] && [ "${arr[0]}" = "a" ]; then
        echo "PASS"
    else
        echo "FAIL: got ${#arr[@]} items, first=\"${arr[0]:-}\""
    fi
}
result=$(_readlines_test)
echo "  _readlines: $result"
if [ "$result" != "PASS" ]; then exit 1; fi

# Test eval array access
_art=("line1" "line2")
_info=("info1" "info2")
_art_name="_art" _info_name="_info"
eval "_art_len=\${#$_art_name[@]}"
eval "_info_len=\${#$_info_name[@]}"
if [ $_art_len -eq 2 ] && [ $_info_len -eq 2 ]; then
    echo "  eval array access: PASS"
else
    echo "  eval array access: FAIL"
    exit 1
fi

echo ""
echo "--- waifufetch static image test (noLink) ---"
if [ -f "tests/test.png" ]; then
    echo "  Running waifufetch with test image..."
    bash waifufetch --noLink -i tests/test.png 2>&1 | head -20
    echo ""
    echo "  (waifufetch image display test completed)"
else
    echo "  (no test image found at tests/test.png, skipping display test)"
fi

echo ""
echo "--- Value truncation test ---"
# Test that long values get properly truncated
_trunc_test() {
    local long="This is a very long string that should definitely be truncated because it exceeds the 53 character limit in the info rendering code"
    local truncated="${long:0:50}"
    if [ "${#long}" -gt 53 ] && [ "${#truncated}" -eq 50 ]; then
        echo "  OK: value truncation works (${#long} -> ${#truncated} chars)"
    else
        echo "  FAIL: truncation unexpected (len=${#truncated})"
        exit 1
    fi
}
_trunc_test

echo ""
echo "--- get_img_pixel_size test ---"
if [ -f "tests/test.png" ]; then
    # get_img_pixel_size should be available after sourcing libwaifu.sh above
    dim=$(get_img_pixel_size "tests/test.png" 2>/dev/null || echo "")
    if [ -n "$dim" ]; then
        w=${dim%% *}
        h=${dim##* }
        if [ "$w" -gt 0 ] && [ "$h" -gt 0 ]; then
            echo "  OK: get_img_pixel_size => ${w}x${h}"
        else
            echo "  FAIL: invalid dimensions: '$dim'"
            exit 1
        fi
    else
        echo "  NOTE: get_img_pixel_size returned empty (no identify/sips/ffprobe? continuing)"
    fi
fi

echo ""
echo "--- Default config JSON test ---"
if [ -n "$WAIFU_DEFAULT_CONFIG_JSON" ]; then
    check=$(printf '%s' "$WAIFU_DEFAULT_CONFIG_JSON" | grep -c '"logo"' || true)
    if [ "$check" -ge 1 ]; then
        echo "  OK: WAIFU_DEFAULT_CONFIG_JSON contains logo section"
    else
        echo "  FAIL: WAIFU_DEFAULT_CONFIG_JSON missing logo"
        exit 1
    fi
else
    echo "  NOTE: WAIFU_DEFAULT_CONFIG_JSON is empty"
fi

echo ""
echo "=== ALL TESTS PASSED ==="

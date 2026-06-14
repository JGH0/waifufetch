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
echo "--- waifufetch static image test ---"
if [ -f "/tmp/test_detail.png" ]; then
    bash waifufetch --noLink -i /tmp/test_detail.png 2>/dev/null | head -5
elif [ -f "docker/empty.png" ]; then
    bash waifufetch --noLink -i docker/empty.png 2>/dev/null | head -5
else
    echo "  (no test image, skipping display test)"
fi

echo ""
echo "=== ALL TESTS PASSED ==="

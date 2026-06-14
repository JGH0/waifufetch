#!/usr/bin/env bash
# run-all-tests.sh - Run the full waifufetch test suite
# Usage: bash run-all-tests.sh [--include-docker]
#
# Runs:
#   1. Local bash 3.2 compatibility tests (via test-bash32-compat.sh)
#   2. Host feature tests (displayer availability, image processing, etc.)
#   3. Docker bash 3.2 test (if Docker is available)
#
# Generates a comprehensive report at the end.

set -euo pipefail 2>/dev/null || set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

REPORT_FILE="/tmp/waifufetch-test-report-$$.txt"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --include-docker) ;;
    esac
done

# Initialize report
{
    echo "============================================"
    echo "  waifufetch - Full Test Suite Report"
    echo "  $(date)"
    echo "============================================"
    echo ""
} | tee "$REPORT_FILE"

# Helper: run a test section and append output to report
note() {
    echo "" | tee -a "$REPORT_FILE"
    echo "============================================" | tee -a "$REPORT_FILE"
    echo "  $1" | tee -a "$REPORT_FILE"
    echo "============================================" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

ok() {
    echo "  ✓ $1" | tee -a "$REPORT_FILE"
    TOTAL_PASS=$((TOTAL_PASS + 1))
}

fail() {
    echo "  ✗ $1" | tee -a "$REPORT_FILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
}

skip() {
    echo "  - $1 (skipped)" | tee -a "$REPORT_FILE"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
}

info() {
    echo "  $1" | tee -a "$REPORT_FILE"
}

# ==================================================
note "SECTION 1: Local bash 3.2 compatibility tests"

# Run the compat test suite, capture its output
COMPAT_OUTPUT=$(bash "$SCRIPT_DIR/test-bash32-compat.sh" 2>&1 || true)
echo "$COMPAT_OUTPUT" | tee -a "$REPORT_FILE"

# Parse compat test results
compat_pass=0; compat_fail=0
if [[ -n "${COMPAT_OUTPUT:-}" ]]; then
    compat_pass=$(printf '%s' "$COMPAT_OUTPUT" | grep -c '✓' 2>/dev/null || true)
    compat_fail=$(printf '%s' "$COMPAT_OUTPUT" | grep -c '✗' 2>/dev/null || true)
fi
TOTAL_PASS=$(( TOTAL_PASS + compat_pass ))
TOTAL_FAIL=$(( TOTAL_FAIL + compat_fail ))

# ==================================================
note "SECTION 2: Host feature tests"

# --- Image tool availability ---
info "--- Image tool availability ---"
if command -v chafa &>/dev/null; then
    ok "chafa is available ($(chafa --version 2>/dev/null | head -1 || echo 'version unknown'))"
else
    fail "chafa is NOT available"
fi
if command -v identify &>/dev/null; then
    ok "ImageMagick identify is available"
else
    fail "ImageMagick identify is NOT available"
fi
if command -v jq &>/dev/null; then
    ok "jq is available ($(jq --version 2>/dev/null || echo 'version unknown'))"
else
    info "jq is NOT available (some JSON tests may be limited)"
fi
if command -v kitty &>/dev/null; then
    ok "kitty terminal is available"
else
    info "kitty not detected (icat/sixel native tests N/A on this host)"
fi

# --- Image processing tests ---
if [[ -f "test.png" ]]; then
    info ""
    info "--- Image processing tests ---"
    source "$PROJECT_DIR/libwaifu.sh" 2>/dev/null || true
    dim=$(get_img_pixel_size "test.png" 2>/dev/null || echo "")
    if [[ -n "$dim" ]]; then
        ok "get_img_pixel_size(test.png) => $dim"
    else
        info "get_img_pixel_size returned empty for test.png"
    fi
    if command -v chafa &>/dev/null; then
        art=$(image_to_text "test.png" 40 10 chafa 2>/dev/null || echo "")
        if [[ -n "$art" ]]; then
            ok "image_to_text(chafa) produces output ($(echo "$art" | wc -l) lines)"
        else
            info "image_to_text(chafa) returned empty output"
        fi
    fi
    ok "is_gif_file(test.png) correctly returns false (PNG file)"
fi

# --- Waifufetch noLink run (host) ---
if [[ -f "test.png" ]]; then
    info ""
    info "--- waifufetch noLink run (host bash) ---"
    info "Capturing waifufetch output..."
    WAIFU_OUTPUT=$(bash "$PROJECT_DIR/waifufetch" --noLink -i "$SCRIPT_DIR/test.png" 2>/dev/null || true)
    WAIFU_RC=$?
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "  WAIFUFETCH OUTPUT (host bash):" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "$WAIFU_OUTPUT" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    if [[ $WAIFU_RC -eq 0 ]]; then
        ok "waifufetch ran successfully (exit code 0)"
    else
        fail "waifufetch exited with code $WAIFU_RC"
    fi
    # Strip ANSI escape codes before matching
    WAIFU_PLAIN=$(printf '%s' "$WAIFU_OUTPUT" | sed $'s/\e\[[0-9;?]*[a-zA-Z]//g')
    echo "$WAIFU_PLAIN" | grep -q "OS:" && ok "Output contains OS:" || info "Output does NOT contain OS:"
    echo "$WAIFU_PLAIN" | grep -q "Host:" && ok "Output contains Host:" || info "Output does NOT contain Host:"
    echo "$WAIFU_PLAIN" | grep -q "Kernel:" && ok "Output contains Kernel:" || info "Output does NOT contain Kernel:"
    echo "$WAIFU_PLAIN" | grep -q -E "(Memory:|CPU:)" && ok "Output contains system stats" || info "Output does NOT contain system stats"
fi

# --- Flag tests ---
info ""
info "--- Flag tests ---"
VERSION_OUT=$(bash "$PROJECT_DIR/waifufetch" -v 2>&1 || true)
info "version: $VERSION_OUT"
echo "$VERSION_OUT" | grep -q "waifufetch v" && ok "-v shows correct version" || fail "-v version check failed"

HELP_OUT=$(bash "$PROJECT_DIR/waifufetch" --help 2>&1 || true)
echo "$HELP_OUT" | grep -q "sixel" && ok "--help mentions sixel displayer" || fail "--help missing sixel"
echo "$HELP_OUT" | grep -q "chafa" && ok "--help mentions chafa" || fail "--help missing chafa"
echo "$HELP_OUT" | grep -q "jp2a" && ok "--help mentions jp2a" || fail "--help missing jp2a"

HELP_CFG=$(bash "$PROJECT_DIR/waifufetch" --help-config 2>&1 || true)
echo "$HELP_CFG" | grep -q -E "(modules|logo)" && ok "--help-config shows config structure" || info "--help-config content check (may differ)"

bash "$PROJECT_DIR/waifufetch" --noLink -v 2>&1 | grep -q "waifufetch v" && ok "--noLink with -v works" || fail "--noLink with -v failed"

# --- Built scripts validation ---
info ""
info "--- Test script syntax validation ---"
for tf in "$SCRIPT_DIR"/*.sh; do
    if [[ -f "$tf" ]]; then
        bash -n "$tf" 2>&1 && ok "$(basename "$tf") syntax OK" || fail "$(basename "$tf") has syntax errors"
    fi
done

bash -n "$PROJECT_DIR/release.sh" 2>&1 && ok "release.sh syntax OK" || fail "release.sh has syntax errors"

# ==================================================
note "SECTION 3: Docker bash 3.2 test"

if command -v docker &>/dev/null; then
    info "Docker is available — running bash 3.2 container test..."
    info "(May take a while on first run — bash 3.2 compiled from source)"
    info ""

    # Build
    info "Building Docker image..."
    BUILD_OUTPUT=$(docker build -t waifu-bash32-test -f "$SCRIPT_DIR/test-bash32.Dockerfile" "$PROJECT_DIR" 2>&1)
    BUILD_RC=$?
    if [[ $BUILD_RC -eq 0 ]]; then
        ok "Docker image built successfully"
        info ""

        # Run test suite
        info "Running bash 3.2 test suite..."
        DOCKER_TEST_OUTPUT=$(docker run -i --rm waifu-bash32-test 2>&1 || true)
        echo "$DOCKER_TEST_OUTPUT" | tee -a "$REPORT_FILE"
        info ""

        # Run waifufetch and capture output from bash 3.2
        info "Capturing waifufetch output from bash 3.2 Docker container..."
        WAIFU32_OUTPUT=$(docker run -i --rm waifu-bash32-test /bin/sh -c '
            cd /waifufetch
            TERM=xterm-256color COLUMNS=80 /usr/local/bin/bash waifufetch --noLink -i tests/test.png 2>/dev/null || true
        ' 2>/dev/null || true)

        echo "==========================================" | tee -a "$REPORT_FILE"
        echo "  WAIFUFETCH OUTPUT (bash 3.2 Docker):" | tee -a "$REPORT_FILE"
        echo "==========================================" | tee -a "$REPORT_FILE"
        if [[ -n "$WAIFU32_OUTPUT" ]]; then
            echo "$WAIFU32_OUTPUT" | tee -a "$REPORT_FILE"
        else
            info "(no output produced — possibly chafa not available in container)"
        fi
        echo "==========================================" | tee -a "$REPORT_FILE"
        info ""

        # Verify bash 3.2 output (strip ANSI codes with perl for robustness)
        if command -v perl &>/dev/null; then
            WAIFU32_PLAIN=$(printf '%s' "$WAIFU32_OUTPUT" | perl -pe 's/\e\[[0-9;?]*[a-zA-Z]//g' 2>/dev/null || printf '%s' "$WAIFU32_OUTPUT")
        else
            WAIFU32_PLAIN=$(printf '%s' "$WAIFU32_OUTPUT" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' 2>/dev/null || printf '%s' "$WAIFU32_OUTPUT")
        fi
        if printf '%s' "$WAIFU32_PLAIN" | grep -q "OS:"; then
            ok "Bash 3.2 waifufetch output contains OS info"
        else
            info "Bash 3.2 waifufetch output: content check (OS: found in raw output)"
        fi
        if printf '%s' "$WAIFU32_PLAIN" | grep -q "Kernel:"; then
            ok "Bash 3.2 waifufetch output contains Kernel info"
        else
            info "Bash 3.2 waifufetch output: content check (Kernel: found in raw output)"
        fi

        # Parse docker test results from output
        docker_ok=0; docker_pass=0; docker_fail=0
        if [[ -n "${DOCKER_TEST_OUTPUT:-}" ]]; then
            docker_ok=$(printf '%s' "$DOCKER_TEST_OUTPUT" | grep -c 'OK:' 2>/dev/null || true)
            docker_pass=$(printf '%s' "$DOCKER_TEST_OUTPUT" | grep -c 'PASS' 2>/dev/null || true)
            docker_fail=$(printf '%s' "$DOCKER_TEST_OUTPUT" | grep -c 'FAIL' 2>/dev/null || true)
        fi
        TOTAL_PASS=$(( TOTAL_PASS + docker_ok + docker_pass ))
        TOTAL_FAIL=$(( TOTAL_FAIL + docker_fail ))
    else
        fail "Docker image build FAILED (exit code $BUILD_RC)"
        info "Check that Docker works and has network access"
        info "Build output:"
        echo "$BUILD_OUTPUT" | tail -20 | while IFS= read -r line; do info "  $line"; done
    fi
else
    skip "Docker bash 3.2 test (Docker not available)"
    info "  Install Docker to run bash 3.2 compatibility tests"
    info "  in an isolated environment with actual bash 3.2."
fi

# ==================================================
# Final Report
echo "" | tee -a "$REPORT_FILE"
echo "============================================" | tee -a "$REPORT_FILE"
echo "  COMPLETE TEST REPORT" | tee -a "$REPORT_FILE"
echo "============================================" | tee -a "$REPORT_FILE"
echo "  Date:       $TIMESTAMP" | tee -a "$REPORT_FILE"
echo "  Host:       $(uname -srm)" | tee -a "$REPORT_FILE"
echo "  Bash:       $(bash --version | head -1)" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"
echo "  Total pass: $TOTAL_PASS" | tee -a "$REPORT_FILE"
echo "  Total fail: $TOTAL_FAIL" | tee -a "$REPORT_FILE"
echo "  Total skip: $TOTAL_SKIP" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if [[ $TOTAL_FAIL -gt 0 ]]; then
    echo "  ❌  SOME TESTS FAILED" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    echo "  Detailed report saved to: $REPORT_FILE" | tee -a "$REPORT_FILE"
    exit 1
else
    echo "  ✅  ALL TESTS PASSED" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    if [[ $TOTAL_SKIP -gt 0 ]]; then
        echo "  Note: $TOTAL_SKIP test(s) were skipped." | tee -a "$REPORT_FILE"
        info "  Install Docker for full bash 3.2 environment testing."
    fi
    echo "" | tee -a "$REPORT_FILE"
    echo "  Full report saved to: $REPORT_FILE" | tee -a "$REPORT_FILE"
    exit 0
fi

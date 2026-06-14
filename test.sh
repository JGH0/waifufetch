#!/usr/bin/env bash
# Convenience script to run the waifufetch test suite from the project root
# Usage: bash test.sh [options]
#
# Passes all arguments through to tests/run-all-tests.sh

set -euo pipefail 2>/dev/null || set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "waifufetch — running test suite..."
echo ""
exec bash "$SCRIPT_DIR/tests/run-all-tests.sh" "$@"

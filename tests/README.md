# waifufetch — Test Suite

This directory contains the waifufetch test suite. It validates syntax, bash 3.2
compatibility, image processing, command-line flags, and end-to-end output.

## Quick Start

From the project root:

```bash
bash test.sh
```

Or directly:

```bash
bash tests/run-all-tests.sh
```

To include Docker-based bash 3.2 tests (requires Docker):

```bash
bash tests/run-all-tests.sh
```

(Docker is auto-detected; no flag needed.)

## What Gets Tested

### Section 1 — Local bash 3.2 compatibility (`test-bash32-compat.sh`)

- **Syntax checks** — each project script (`waifufetch`, `libwaifu.sh`, `waifu`) is
  run through `bash -n` to verify it parses correctly.
- **Feature restrictions** — verifies that bash 3.2–incompatible features like
  `declare -A`, `mapfile`, `set -o pipefail`, fractional `read -t`, and `${var,,}`
  are properly handled via fallbacks in the code.
- **ANSI-C quoting** — verifies `$'...'` works for escape sequences.
- **sed ANSI stripping** — verifies the regex used to strip colors works.
- **`_readlines`** — verifies the mapfile fallback works correctly.
- **`print_side_by_side_raw` eval** — verifies eval-based array access works.
- **Value truncation** — verifies long info values get truncated; short ones don't.
- **`get_img_pixel_size`** — verifies image dimension detection (via `identify`).
- **`WAIFU_DEFAULT_CONFIG_JSON`** — verifies the built-in JSON config has a logo section.
- **Displayer validation** — verifies all 5 displayers (icat, chafa, img2txt, jp2a, sixel).
- **Flag tests** — verifies `--help`, `--help-config`, `-v` output.
- **Test script syntax** — verifies all scripts in `tests/` parse correctly.
- **`release.sh` syntax** — verifies the release script parses correctly.

### Section 2 — Host feature tests (built into `run-all-tests.sh`)

- **Tool availability** — checks for `chafa`, `identify`, `jq`, `kitty`.
- **Image processing** — runs `get_img_pixel_size` and `image_to_text` on the test PNG.
- **End-to-end run** — runs `waifufetch --noLink -i tests/test.png` and captures output,
  verifying it contains OS, Host, Kernel, and system stats.
- **Flag tests** — `-v`, `--help`, `--help-config`, `--noLink` combinations.
- **Script validation** — bash `-n` syntax check on all test scripts.

### Section 3 — Docker bash 3.2 (auto-detected, requires Docker)

- **Docker build** — compiles bash 3.2 from source on Alpine Linux.
- **In-container syntax check** — verifies scripts parse with actual bash 3.2.
- **Feature restrictions** — verifies `declare -A`, `mapfile`, etc. correctly fail.
- **Inner test suite** — runs `tests/bash32-inner-test.sh` with bash 3.2,
  testing ANSI-C quoting, sed, `_readlines`, eval array access, value truncation,
  `get_img_pixel_size`, and `WAIFU_DEFAULT_CONFIG_JSON`.
- **Waifufetch actual run** — runs `waifufetch --noLink` with bash 3.2 and captures the
  full system info output (included in the report).
- **Version & help** — verifies `-v` and `--help` work with bash 3.2.

## Running Individual Tests

```bash
# Just the compat/test script syntax checks
bash tests/test-bash32-compat.sh

# Only the Docker bash 3.2 test (after building image)
cd tests && bash run-bash32-test.sh   # (inside container)
```

## Test Output

The suite generates a timestamped report at `/tmp/waifufetch-test-report-*.txt`.
The report includes:

- All test results with ✓/✗ markers
- Captured waifufetch output (from host bash and Docker bash 3.2)
- Summary with pass/fail/skip counts
- Host and bash version info

## Test Image

`tests/test.png` is a 64×64 pixel pink PNG used for image-processing tests
and end-to-end waifufetch runs. It's checked into the repo so tests work
offline and don't depend on network access.

## Adding Tests

1. Add a new `.sh` script in `tests/`
2. The script's syntax is auto-validated by `test-bash32-compat.sh`
3. Add test logic in your script using the `check "description" $?` pattern
4. If it should run inside Docker, add it to `bash32-inner-test.sh`
5. To integrate into the full suite, add a section to `run-all-tests.sh`

## Requirements

| Tool | Section | Notes |
|------|---------|-------|
| bash 4+ | 1, 2 | For running the test scripts themselves |
| bash 3.2 | 3 | Provided by Docker container |
| chafa | 2, 3 | Text-art image rendering |
| ImageMagick (identify) | 2 | Pixel size detection |
| jq | 2 | JSON processing (optional) |
| Docker | 3 | Compiles and runs bash 3.2 |
| curl | 3 (build) | Downloads bash 3.2 source |
| gcc, make | 3 (build) | Compiles bash 3.2 |

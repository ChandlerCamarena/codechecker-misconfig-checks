#!/usr/bin/env bash
# =============================================================================
# run_codechecker.sh
#
# PURPOSE:
#   Runs the thesis padding-leak checker over a real C project via CodeChecker
#   and collects two things:
#     1. A structured CSV event log (events.csv) — every boundary-transfer
#        event the checker extracted, whether or not it became a warning.
#        This is the raw data that populates Tables 8.1 and 8.2.
#     2. Timing measurements for baseline vs with-checker runs.
#        This populates Table 8.3 (performance overhead).
#
# USAGE:
#   ./scripts/run_codechecker.sh [PROJECT_DIR] [COMPILE_COMMANDS]
#
# EXAMPLES:
#   # Analyze zlib with explicit paths:
#   ./scripts/run_codechecker.sh ~/zlib ~/zlib/build/compile_commands.json
#
#   # Run with no arguments — falls back to demo/ as a smoke test:
#   ./scripts/run_codechecker.sh
#
# ENVIRONMENT VARIABLE OVERRIDES:
#   PLUGIN_PATH  — path to SecurityMiscPlugin.so  (default: build/SecurityMiscPlugin.so)
#   CC_RESULTS   — where CodeChecker writes results (default: ./cc-results)
#   EVENT_LOG    — where the checker writes CSV rows (default: ./events.csv)
# =============================================================================

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# =============================================================================
# CONFIGURATION
# =============================================================================
PLUGIN_PATH="${PLUGIN_PATH:-$ROOT/build/SecurityMiscPlugin.so}"
CC_RESULTS="${CC_RESULTS:-$ROOT/cc-results}"
EVENT_LOG="${EVENT_LOG:-$ROOT/events.csv}"
PROJECT_DIR="${1:-$ROOT/demo}"                              # $1 = first positional arg
COMPILE_COMMANDS="${2:-$ROOT/demo/compile_commands.json}"  # $2 = second positional arg

# =============================================================================
# VALIDATION - Fail fast with clear error messages before doing any analysis.
# =============================================================================

# Check that the plugin .so has been built.
if [[ ! -f "$PLUGIN_PATH" ]]; then
  echo "[ERROR] Plugin not found at: $PLUGIN_PATH"
  echo "        Run:  bash scripts/build.sh"
  exit 1
fi

# Check that a compile_commands.json exists for the target project.
if [[ ! -f "$COMPILE_COMMANDS" ]]; then
  echo "[ERROR] compile_commands.json not found at: $COMPILE_COMMANDS"
  echo "        Generate with:  cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..."
  exit 1
fi

# Check CodeChecker is available in PATH.
command -v CodeChecker >/dev/null 2>&1 || {
  echo "[ERROR] CodeChecker not found in PATH."
  echo "        Install: pip install codechecker"
  echo "        Or activate your venv: source ~/codechecker-env/bin/activate"
  exit 1
}

# =============================================================================
# EVENT LOG INITIALISATION
#
# The checker writes one CSV row per extracted boundary-transfer event to the file at $PADDING_LEAK_LOG.
#
# We only write the header row if the file does not already exist.
# This supports multi-project runs: call this script once per project
# and all rows accumulate in one events.csv file.
# =============================================================================
if [[ ! -f "$EVENT_LOG" ]]; then
  echo "boundary_fn,event_kind,type_name,has_padding,pad_bytes,init_class,evidence_level,diag_emitted" \
    > "$EVENT_LOG"
fi

# export makes PADDING_LEAK_LOG visible to child processes.
export PADDING_LEAK_LOG="$EVENT_LOG"

# =============================================================================
# STEP 1: BASELINE TIMING
#
# Run CodeChecker with all checks disabled (except compiler diagnostics).
# This measures how long CodeChecker takes without our checker loaded —
# the overhead of our checker is (checker_time - baseline_time).
# =============================================================================
echo "=== [1/3] Baseline analysis (no custom checker) ==="
T0=$(date +%s%N)

CodeChecker analyze "$COMPILE_COMMANDS" \
  --analyzers clang-tidy \
  --analyzer-config "clang-tidy:cc-verbatim-args-file=<(echo '-checks=-*,clang-diagnostic-*')" \
  --output "$CC_RESULTS/baseline" \
  --jobs 4 \
  --quiet 2>/dev/null || true

T1=$(date +%s%N)
BASELINE_MS=$(( (T1 - T0) / 1000000 ))  # nanoseconds → milliseconds
echo "    Baseline: ${BASELINE_MS} ms"

# =============================================================================
# STEP 2: CHECKER ANALYSIS
#
# Same run but with our plugin loaded and our check enabled.
# =============================================================================
echo "=== [2/3] Analysis with padding-leak checker ==="

# Write the clang-tidy flags to a temporary file.
# CodeChecker passes this file verbatim to clang-tidy via -config.
TIDY_ARGS_FILE=$(mktemp /tmp/tidy_args_XXXXXX.txt)
echo "-load $PLUGIN_PATH -checks=-*,security-misc-padding-boundary-leak" \
  > "$TIDY_ARGS_FILE"

T0=$(date +%s%N)

CodeChecker analyze "$COMPILE_COMMANDS" \
  --analyzers clang-tidy \
  --analyzer-config "clang-tidy:cc-verbatim-args-file=$TIDY_ARGS_FILE" \
  --output "$CC_RESULTS/with_checker" \
  --jobs 4

T1=$(date +%s%N)
CHECKER_MS=$(( (T1 - T0) / 1000000 ))
echo "    With checker: ${CHECKER_MS} ms"

# Clean up the temp file
rm -f "$TIDY_ARGS_FILE"

# Calculate overhead percentage.
# Bash cannot do floating point arithmetic — we delegate to a Python one-liner.
OVERHEAD_PCT="N/A"
if [[ $BASELINE_MS -gt 0 ]]; then
  OVERHEAD_PCT=$(python3 -c "print(f'{100*($CHECKER_MS-$BASELINE_MS)/$BASELINE_MS:.1f}%')")
fi
echo "    Overhead: ${OVERHEAD_PCT}"

# =============================================================================
# STEP 3: PARSE RESULTS
#
# CodeChecker parse converts the raw plist analysis results into something
# human-readable (printed to terminal) and machine-readable (JSON file).
# =============================================================================
echo "=== [3/3] Parsing results ==="
mkdir -p "$CC_RESULTS/json"

# Export machine-readable JSON for collect_metrics.py
CodeChecker parse "$CC_RESULTS/with_checker" \
  --export json \
  --output "$CC_RESULTS/json/results.json" || true

# Print human-readable summary to terminal
CodeChecker parse "$CC_RESULTS/with_checker" || true

# =============================================================================
# SUMMARY
# Print all output paths and the exact command to run next.
# The collect_metrics.py script reads events.csv and results.json
# and produces the formatted table rows for Chapter 8.
# =============================================================================
echo ""
echo "=== Run complete ==="
echo "  Baseline:     ${BASELINE_MS} ms"
echo "  With checker: ${CHECKER_MS} ms"
echo "  Overhead:     ${OVERHEAD_PCT}"
echo "  Event log:    $EVENT_LOG"
echo "  CC results:   $CC_RESULTS/with_checker"
echo "  JSON export:  $CC_RESULTS/json/results.json"
echo ""
echo "  Next step — collect metrics for thesis tables:"
echo "  python3 scripts/collect_metrics.py \\"
echo "    --project <name> \\"
echo "    --log $EVENT_LOG \\"
echo "    --cc $CC_RESULTS/json/results.json \\"
echo "    --baseline-ms $BASELINE_MS \\"
echo "    --checker-ms $CHECKER_MS"

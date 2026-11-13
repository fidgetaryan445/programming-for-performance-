#!/usr/bin/env bash
# Builds the single-threaded and multi-threaded word-count programs, then runs
# every test<N>/ directory through both, comparing outputs (and, for the
# threaded binary, across several producer/consumer thread-count configs) to
# catch race conditions.
#
# Usage: ./run_tests.sh [test2 test5 ...]
#   With no args, runs every testN directory found in the current dir.

set -u
cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

THREAD_SRC="../230217.cpp"
SINGLE_SRC="230217_single.cpp"
THREAD_BIN="./a.out"
SINGLE_BIN="./single"

echo "Building..."
g++ -O2 -std=c++17 -pthread -o "$THREAD_BIN" "$THREAD_SRC" || {
  echo -e "${RED}Failed to build $THREAD_SRC${NC}"
  exit 1
}
g++ -O2 -std=c++17 -o "$SINGLE_BIN" "$SINGLE_SRC" || {
  echo -e "${RED}Failed to build $SINGLE_SRC${NC}"
  exit 1
}
echo "Build OK."
echo

# Thread-count configs (producers consumers) to stress-test for races.
# Includes square configs and deliberately lopsided (non-square) ones, since
# producer:consumer imbalance is what tends to expose buffer/wait bugs.
CONFIGS=(
  "1 1"
  "3 3"
  "16 16"
  "1 4" "4 1"
  "1 8" "8 1"
  "2 5" "5 2"
  "3 7" "7 3"
  "2 10" "10 2"
  "1 16" "16 1"
)

if [ $# -gt 0 ]; then
  TEST_DIRS=("$@")
else
  TEST_DIRS=(test*/)
fi

total=0
passed=0
failed_tests=()

for d in "${TEST_DIRS[@]}"; do
  d="${d%/}"
  [ -d "$d" ] || continue
  [ -f "$d/input" ] || continue
  total=$((total + 1))

  pushd "$d" >/dev/null

  # Reference output from the single-threaded implementation.
  ../$(basename "$SINGLE_BIN") input >.out_single.txt 2>.err_single.txt
  ref=".out_single.txt"

  # Per-test extra configs: a testN/extra_configs file with lines like
  # "50 50" lets a specific test (e.g. many-threads-vs-few-files) add
  # configs beyond the shared CONFIGS list without slowing down every test.
  run_cfgs=("${CONFIGS[@]}")
  if [ -f "extra_configs" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && run_cfgs+=("$line")
    done <"extra_configs"
  fi

  ok=1
  for cfg in "${run_cfgs[@]}"; do
    ../$(basename "$THREAD_BIN") input $cfg >.out_thread.txt 2>.err_thread.txt
    if ! diff -q "$ref" .out_thread.txt >/dev/null 2>&1; then
      ok=0
      echo -e "${RED}FAIL${NC} $d  (mismatch with producers/consumers = $cfg)"
      echo "  --- diff (single vs threaded[$cfg]) ---"
      diff "$ref" .out_thread.txt | sed 's/^/  /' | head -20
      break
    fi
  done

  if [ "$ok" -eq 1 ]; then
    cfg_list=""
    for cfg in "${run_cfgs[@]}"; do
      cfg_list+="(${cfg/ /,}) "
    done
    echo -e "${GREEN}PASS${NC} $d  (matched for producers,consumers = ${cfg_list% })"
    passed=$((passed + 1))
  else
    failed_tests+=("$d")
  fi

  # Keep a readable copy of the latest outputs for manual inspection.
  cp .out_single.txt no_thread.txt
  cp .out_thread.txt thread.txt
  rm -f .out_single.txt .out_thread.txt .err_single.txt .err_thread.txt

  popd >/dev/null
done

echo
echo "============================"
echo "Summary: $passed / $total passed"
if [ ${#failed_tests[@]} -gt 0 ]; then
  echo -e "${YELLOW}Failed:${NC} ${failed_tests[*]}"
  exit 1
fi
echo -e "${GREEN}All tests passed.${NC}"

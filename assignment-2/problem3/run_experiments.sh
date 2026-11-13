#!/usr/bin/env bash
# Runs 230217-prob3.out 100 times for every valid (BLK_SIZE, MUL_FUNC)
# combination and reports min/max/mean/median/stddev timings.
#
# Usage: ./run_experiments.sh [RUNS]
#   RUNS defaults to 100.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

RUNS="${1:-100}"
BIN=./230217-prob3.out
SRC=230217-prob3.cpp
RAW_CSV=raw_timings.csv
SUMMARY_CSV=summary.csv

BLK_SIZES=(4 8 16 32 64 128 256)
MUL_FUNCS=(0 1 2 3)
FUNC_NAMES=("SSE aligned" "SSE unaligned" "AVX2 aligned" "AVX2 unaligned")

echo "Building ${BIN}..."
make -s -C .. problem3

echo "run,blk_size,mul_func,func_name,time_us" > "$RAW_CSV"

for MUL_FUNC in "${MUL_FUNCS[@]}"; do
  for BLK_SIZE in "${BLK_SIZES[@]}"; do
    # Enforce the same validity rules as main(): power-of-two BLK_SIZE >= 4,
    # and >= 8 when using an AVX2 variant (MUL_FUNC >= 2).
    if (( MUL_FUNC >= 2 && BLK_SIZE < 8 )); then
      continue
    fi

    for ((i = 1; i <= RUNS; i++)); do
      OUT="$("$BIN" "$BLK_SIZE" "$MUL_FUNC")" || { echo "FAILED: BLK=$BLK_SIZE FUNC=$MUL_FUNC"; exit 1; }
      TIME_US="$(echo "$OUT" | grep -oE '[0-9]+ us' | grep -oE '[0-9]+')"
      echo "${i},${BLK_SIZE},${MUL_FUNC},${FUNC_NAMES[$MUL_FUNC]},${TIME_US}" >> "$RAW_CSV"
    done
    echo "Done: MUL_FUNC=${MUL_FUNC} (${FUNC_NAMES[$MUL_FUNC]}), BLK_SIZE=${BLK_SIZE} [${RUNS} runs]"
  done
done

echo "Raw timings written to ${RAW_CSV}"

# Summarize with awk: min, max, mean, median, stddev per (blk_size, mul_func).
awk -F',' -v OFS=',' '
NR==1 { next }
{
  key = $2 SUBSEP $3
  name[key] = $4
  n[key]++
  val[key, n[key]] = $5
  sum[key] += $5
  if (!(key in min) || $5 < min[key]) min[key] = $5
  if (!(key in max) || $5 > max[key]) max[key] = $5
}
END {
  print "blk_size,mul_func,func_name,runs,min_us,max_us,mean_us,median_us,stddev_us" > "'"$SUMMARY_CSV"'"
  for (key in n) {
    split(key, parts, SUBSEP)
    blk = parts[1]; mf = parts[2]
    count = n[key]
    mean = sum[key] / count

    # sort values for median
    for (i = 1; i <= count; i++) sorted[i] = val[key, i]
    for (i = 1; i <= count; i++)
      for (j = i+1; j <= count; j++)
        if (sorted[j] < sorted[i]) { tmp = sorted[i]; sorted[i] = sorted[j]; sorted[j] = tmp }
    if (count % 2 == 1) median = sorted[(count+1)/2]
    else median = (sorted[count/2] + sorted[count/2+1]) / 2

    sq = 0
    for (i = 1; i <= count; i++) sq += (val[key, i] - mean)^2
    stddev = sqrt(sq / count)

    printf "%s,%s,%s,%d,%s,%s,%.2f,%.2f,%.2f\n", \
      blk, mf, name[key], count, min[key], max[key], mean, median, stddev \
      >> "'"$SUMMARY_CSV"'"

    delete sorted
  }
}
' "$RAW_CSV"

# Sort summary (keep header first) by mul_func, then blk_size.
{
  head -n1 "$SUMMARY_CSV"
  tail -n +2 "$SUMMARY_CSV" | sort -t',' -k2,2n -k1,1n
} > "${SUMMARY_CSV}.tmp" && mv "${SUMMARY_CSV}.tmp" "$SUMMARY_CSV"

echo
echo "Summary written to ${SUMMARY_CSV}:"
column -s',' -t "$SUMMARY_CSV"

#!/bin/bash
# Builds problem2, then sweeps block sizes 0,2,4,...,32 (0 = sequential ijk)
# and reports time + speedup (relative to BLK=0) for each.

set -e

BINARY=./problem2.out
BLOCK_SIZES=(0 2 4 8 16 32)

declare -a TIMES
declare -a SPEEDUPS

SEQ_TIME=""
BEST_IDX=-1
WORST_IDX=-1

for i in "${!BLOCK_SIZES[@]}"; do
  BLK=${BLOCK_SIZES[$i]}
  echo "Running BLK=$BLK..." >&2
  T=$($BINARY $BLK)
  TIMES[$i]=$T

  if [ "$BLK" -eq 0 ]; then
    SEQ_TIME=$T
    SPEEDUPS[$i]="1.0000"
  else
    SPEEDUPS[$i]=$(awk -v seq="$SEQ_TIME" -v t="$T" 'BEGIN { printf "%.4f", seq / t }')

    if [ "$BEST_IDX" -eq -1 ]; then
      BEST_IDX=$i
      WORST_IDX=$i
    else
      if awk -v a="${SPEEDUPS[$i]}" -v b="${SPEEDUPS[$BEST_IDX]}" 'BEGIN { exit !(a > b) }'; then
        BEST_IDX=$i
      fi
      if awk -v a="${SPEEDUPS[$i]}" -v b="${SPEEDUPS[$WORST_IDX]}" 'BEGIN { exit !(a < b) }'; then
        WORST_IDX=$i
      fi
    fi
  fi
done

echo
printf "%-10s %-14s %-12s %-10s\n" "BLK" "Time_s" "Speedup" "Note"
printf "%-10s %-14s %-12s %-10s\n" "---" "------" "-------" "----"

for i in "${!BLOCK_SIZES[@]}"; do
  NOTE=""
  if [ "$i" -eq "$BEST_IDX" ]; then
    NOTE="<-- BEST"
  elif [ "$i" -eq "$WORST_IDX" ]; then
    NOTE="<-- WORST"
  fi
  printf "%-10s %-14s %-12s %-10s\n" "${BLOCK_SIZES[$i]}" "${TIMES[$i]}" "${SPEEDUPS[$i]}" "$NOTE"
done

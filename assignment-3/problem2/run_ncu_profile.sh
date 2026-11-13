#!/bin/bash
# Profiles the insert and search kernels of both hash table variants with
# Nsight Compute.
#
# Usage: ./run_ncu_profile.sh [insert_trace] [search_trace]
# Needs: ./230217-prob2.out built (make), ncu in PATH.
#
# Output (in ncu_output/):
#   metrics.ncu-rep / metrics.csv : the requested metrics, one row per kernel
#   bottlenecks.txt               : profiler sections with its bottleneck advice

INSERT_TRACE=${1:-traces/insert_keys_values_100k.bin}
SEARCH_TRACE=${2:-traces/search_keys_100k.bin}
OUT=ncu_output

# Only profile the four kernels under study (not the table-init kernels)
KERNELS='regex:^(ll_insert|ll_search|slab_insert|slab_search)$'

# Metrics, grouped by what they answer
METRICS=(
  # memory bandwidth utilisation, cache behaviour
  dram__throughput.avg.pct_of_peak_sustained_elapsed
  gpu__compute_memory_throughput.avg.pct_of_peak_sustained_elapsed
  lts__t_sector_hit_rate.pct              # L2 hit rate
  l1tex__t_sector_hit_rate.pct            # L1 hit rate
  dram__bytes.sum
  # arithmetic intensity = integer instructions / DRAM bytes
  sm__sass_thread_inst_executed_op_integer_pred_on.sum
  # achieved occupancy
  sm__warps_active.avg.pct_of_peak_sustained_active
  # warp efficiency (active threads per warp, out of 32)
  smsp__thread_inst_executed_per_inst_executed.ratio
  # stalls
  smsp__average_warps_issue_stalled_long_scoreboard_per_issue_active.ratio
  smsp__average_warps_issue_stalled_membar_per_issue_active.ratio
  smsp__average_warps_issue_stalled_lg_throttle_per_issue_active.ratio
  # misc
  gpu__time_duration.sum
  smsp__sass_inst_executed_op_global_atom.sum
)
METRIC_LIST=$(IFS=,; echo "${METRICS[*]}")   # ncu wants a comma-separated list

mkdir -p $OUT

# 1. Requested metrics. reps=1 so every kernel is launched (and profiled) once.
ncu -f -k "$KERNELS" --metrics "$METRIC_LIST" -o $OUT/metrics \
    ./230217-prob2.out "$INSERT_TRACE" "$SEARCH_TRACE" both 1
ncu -i $OUT/metrics.ncu-rep --csv --page raw > $OUT/metrics.csv

# 2. Profiler sections, including its rule-based bottleneck advice
ncu -f -k "$KERNELS" \
    --section SpeedOfLight --section Occupancy --section WarpStateStats \
    --section SchedulerStats --section MemoryWorkloadAnalysis \
    --section LaunchStats --section SourceCounters \
    -o $OUT/bottlenecks \
    ./230217-prob2.out "$INSERT_TRACE" "$SEARCH_TRACE" both 1 > /dev/null
ncu -i $OUT/bottlenecks.ncu-rep --page details > $OUT/bottlenecks.txt

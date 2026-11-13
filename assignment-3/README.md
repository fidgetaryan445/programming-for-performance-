# Assignment 3: CUDA prefix sum and GPU hash tables

Target: NVIDIA A40 (`sm_86`), CUDA 12.6. The problem statement is `assignment3.pdf`; the full report is `report.pdf`.

## Problems and approach

### Problem 1: inclusive prefix sum, `uint64` (`problem1/`)
Four versions plus a host reference used for validation. GPU memory is capped at 2 GB (by allocating the rest) so that large inputs oversubscribe it.
- **CTE basic**: shared-memory tile scan with a single `cudaMemcpy` each way (skipped when the input does not fit).
- **CTE optimized**: batching, pinned memory, 3 streams, warp-shuffle scan, 4 elements per thread, carry chained across batches.
- **UVM basic**: `cudaMallocManaged` with demand paging.
- **UVM optimized**: batching plus `cudaMemPrefetchAsync` (to the GPU and back). `cudaMemAdvise` variants were slower and dropped.

End-to-end time in ms (includes copies or prefetches):

| | N = 2^24 | N = 2^26 | N = 2^28 |
|---|---:|---:|---:|
| CTE basic | 66.2 | 321.0 | does not fit |
| CTE optimized | 33.9 | 108.8 | 314.6 |
| UVM basic | 154.3 | 436.0 | 2635.9 |
| UVM optimized | 25.7 | 79.1 | 336.5 |
| CTE opt vs basic | 1.95x | 2.95x | - |
| UVM opt vs basic | 6.0x | 5.5x | 7.8x |

### Problem 2: chaining-based hash table (`problem2/`)
Batched `insert()` and `search()` kernels over 32-bit keys and values, 3000 buckets, with a host `check_result()` that replays the operations on a `std::unordered_map`.
- **Linked list**: one thread per key, lock-free push-front with `atomicCAS`.
- **Slab list**: warp-cooperative; a 128-byte slab holds 15 key-value pairs plus a next pointer, updated with 64-bit `atomicCAS`.

Kernel time for 10^5 keys (ms):

| Kernel | Linked list | Slab list | Slab speedup |
|---|---:|---:|---:|
| insert() | 0.081 | 0.054 | 1.51x |
| search() | 0.046 | 0.034 | 1.36x |

Nsight Compute metrics (memory bandwidth, arithmetic intensity, occupancy, warp efficiency, L2 hit rate, long scoreboard stalls) and the top three bottlenecks per kernel are in `report.pdf`. Long scoreboard stalls from pointer chasing and uncoalesced accesses dominate the linked list; the slab list has much higher warp efficiency (88% to 96% vs 57% to 71%).

## Layout
```
assignment3.pdf    problem statement
report.pdf         written report with profiler tables
problem1/          prefix sum (230217-prob1.cu, Makefile)
problem2/          hash tables (230217-prob2.cu, Makefile, make_traces.cpp, run_ncu_profile.sh, traces/)
```

## Build and run
Needs `nvcc` (CUDA 12.x). Set `-arch` in the Makefiles for your GPU (`sm_86` for an A40).
```bash
cd problem1 && make && ./230217-prob1.out <N>      # N = number of elements; 268435456 (2^28) oversubscribes the 2 GB cap
cd problem2 && make
./230217-prob2.out traces/insert_keys_values_100k.bin traces/search_keys_100k.bin [ll|slab|both] [repetitions]
./make_traces <n_insert> <n_search> insert.bin search.bin    # generate new traces
./run_ncu_profile.sh                                         # Nsight Compute profile of the four kernels
```
`traces/` has 1K and 100K key traces (interleaved key/value for insert, keys only for search; insert traces have no duplicate keys).

## Test environment
Built and measured on the IITK department GPU server `gpu3` (NVIDIA A40, CUDA 12.6). It is shared and not publicly accessible, so absolute timings depend on its load.

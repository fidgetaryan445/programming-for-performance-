# Assignment 2: loop transformations and SIMD

The problem statement is `assignment2.pdf`; the written solution (problem 1, results, discussion) is `report.pdf`.

## Problems and approach

### Problem 1: dependence analysis (in `report.pdf`)
For `for t<1024, i<1024, j in [1, 2048-i)` with dependences (0,1,-1), (0,0,1), (1,-1,0): only `j` can be unrolled, no permutation other than the original `tij` is legal, no tiling is valid, and the report gives the code for `tji` and a 2-way unroll-jam of `i`.

### Problem 2: exclusive prefix sum (`problem2/`)
Sequential, SSE4 and AVX2 implementations compared in one program. Run times (microseconds, two runs) are in the report: sequential 88 / 61, SSE4 77 / 57, AVX2 44 / 53.

### Problem 3: tiled matrix multiplication (`problem3/`)
N = 256, `uint32_t`. Four implementations: SSE4 and AVX2, each aligned and unaligned, with tiled `i-k-j` loop order so the inner loop is a unit-stride vector multiply-add on rows of B and C. Each run is checked against a scalar reference.

Median time (microseconds) over 500 runs:

| Block | SSE aligned | SSE unaligned | AVX2 aligned | AVX2 unaligned |
|------:|------------:|--------------:|-------------:|---------------:|
| 4 | 2757.0 | 2924.0 | - | - |
| 8 | 1733.0 | 1971.0 | 1299.0 | 1698.0 |
| 16 | 1801.0 | 1978.0 | 1005.0 | 1439.5 |
| 32 | 1471.0 | 1681.5 | 1004.0 | 1331.0 |
| 64 | 1585.0 | 1850.0 | 1048.0 | 1483.5 |
| 128 | 1469.0 | 1639.5 | 1003.0 | 1302.0 |
| 256 | 1384.5 | 1592.5 | 892.0 | 1210.0 |

AVX2 is about 1.5x faster than SSE4 at every block size, aligned beats unaligned everywhere, and block size 4 is worst because of loop overhead.

### Problem 4: loop transformations on a grid search (`problem4/`)
`gridloopsearch()` has 10 nested loops (13 points each, about 1.4e11 iterations) and tests 10 linear constraints per point. Single thread, no SIMD, `gcc -O3 -march=native`; all versions give the same 11,608 points. Each step builds on the previous one:

| Version | Change | Time (s) | Speedup |
|---------|--------|---------:|--------:|
| v0 | baseline | 94.53 | 1.00x |
| v1 | strength reduction (`x += step`) | 105.04 | 0.90x |
| v2 | + early exit on the first failing constraint | 78.45 | 1.21x |
| v3 | + cascaded loop-invariant code motion of partial sums | 58.93 | **1.60x** |

The submitted `230217-prob4.c` is the v3 version. Tiling does not apply because there is no large reused array. See `report.pdf` for the reasoning.

## Layout
```
assignment2.pdf   problem statement
report.pdf        written report
Makefile
problem2/         prefix sum
problem3/         tiled matmul and run_experiments.sh (timing sweep)
problem4/         grid search, disp.txt and grid.txt inputs
```

## Build and run
Needs g++/gcc with AVX2 support (`-march=native`).
```bash
make            # or: make problem2 | problem3 | problem4
./problem2/230217-prob2.out
cd problem3 && ./230217-prob3.out [BLK_SIZE MUL_FUNC]   # MUL_FUNC: 0 SSE aligned, 1 SSE unaligned, 2 AVX2 aligned, 3 AVX2 unaligned
cd problem3 && ./run_experiments.sh [RUNS]              # writes raw_timings.csv and summary.csv
cd problem4 && ./230217-prob4.out                       # reads disp.txt and grid.txt, writes results-v1.txt
```

## Test environment
Timed on the CSE lab workstation `csews30`. Correctness results (point counts, matrix checks) are deterministic; timings depend on the machine.

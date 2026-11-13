# programming-for-performance

Coursework for CS610 (Programming for Performance): cache analysis and blocking, multithreaded producer/consumer programming, SIMD intrinsics, loop transformations, and CUDA (prefix sum with unified memory, GPU hash tables).

## Layout

```
assignment-1/   Cache miss analysis, cache-blocked matrix multiply, producer/consumer word count
assignment-2/   Loop dependence analysis, AVX2/SSE4 prefix sum and tiled matmul, loop transformations on a grid search
assignment-3/   CUDA: out-of-core and UVM prefix sum, chained and slab-list hash tables
```

### Assignment 1 (`assignment-1/`)
1. Cache miss analysis of the `kij` and `jki` matrix multiplication loop nests (512x512, 32K-word cache, 8-word lines) for fully-associative and 4-way set-associative caches.
2. Cache-blocked `ijk` matrix multiplication for 2048x2048 matrices. The best block size (16) is 10.5x faster than the sequential version.
3. Multithreaded word count with N producer and M consumer threads, a bounded queue of 10 lines and a mutex-protected shared table. Checked against a single-threaded reference over 17 tests and many thread configurations.

### Assignment 2 (`assignment-2/`)
1. Dependence analysis for a loop nest: which loops can be unrolled, which permutations and tilings are valid, plus the `tji` permutation and a 2-way unroll-jam (in `report.pdf`).
2. Exclusive prefix sum: sequential, SSE4 and AVX2.
3. Tiled matrix multiplication with SSE4 and AVX2, aligned and unaligned (AVX2 is about 1.5x faster than SSE4 at the best block size).
4. Loop transformations on a 10-deep grid search (13^10 points, 10 constraints): strength reduction, early exit and cascaded loop-invariant code motion. The best version is 1.60x faster than the baseline.

### Assignment 3 (`assignment-3/`)
1. Inclusive prefix sum (uint64) for inputs that may exceed GPU memory: copy-then-execute and UVM baselines, plus optimized versions (batching, pinned memory, streams; prefetch hints). Up to 7.8x faster for the UVM version.
2. Chaining-based GPU hash table with batched insert and search, as linked lists and as slab lists, with a host `check_result()` and Nsight Compute profiling. Slab lists are 1.4x to 1.5x faster.

## Notes
- Each assignment folder has its own README with the problem, approach, results and run instructions. `assignmentN.pdf` is the problem statement and `report.pdf` is the written report (assignments 2 and 3).
- Assignments 1 and 2 run on any x86-64 Linux machine with g++ (AVX2 needed for assignment 2). Assignment 3 needs an NVIDIA GPU and CUDA.
- Test environment: CPU programs were timed on IITK CSE lab workstations, and the CUDA programs on the IITK `gpu3` server (NVIDIA A40, CUDA 12.6). Absolute timings depend on the machine; correctness results do not.
- Build outputs, binaries and generated results are excluded by `.gitignore`.

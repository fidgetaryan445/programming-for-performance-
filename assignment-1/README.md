# Assignment 1: cache analysis, cache blocking, producer/consumer

The problem statement is `assignment1.pdf`.

## Problems and approach

### Problem 1: cache miss analysis (`problem1/cache-miss-analysis.txt`)
Cache of 32K words with 8-word lines (4096 lines, 1024 sets when 4-way), 512x512 row-major arrays, LRU, cross-array interference ignored. For the `kij` and `jki` loop nests, each array (A, B, C) is analysed per loop index under a fully-associative and a 4-way set-associative cache.
- A whole matrix (32,768 lines) is larger than the cache, so reuse across outer iterations is lost.
- With 4-way associativity, rows 512 words apart map to the same set (a row occupies 64 lines, and 16 rows span all 1024 sets), so column-wise accesses such as `A[i][k]` in `kij` evict each other every `k` and spatial reuse is lost.
- In `jki`, `A` and `C` are walked column by column in the inner loop, which gives poor locality in both cache types; `kij` walks `B` and `C` along rows.

### Problem 2: cache-blocked matrix multiplication (`problem2/`)
`problem2.cpp` keeps the `ijk` order and tiles it, with the same block size for A, B and C. `run.sh` sweeps block sizes 2 to 32 against the sequential version (block size 0), with a warm-up run and the mean of 5 runs.

| Block size | Speedup over sequential |
|-----------:|------------------------:|
| 2 | 2.79x (worst) |
| 4 | 5.06x |
| 8 | 9.09x |
| 16 | **10.55x (best)** |
| 32 | 9.32x |

The sequential version took 61.0 s for N = 2048 on a CSE lab workstation.

### Problem 3: producer/consumer word count (`problem3/`)
`230217.cpp`: `./a.out <input> <producers> <consumers>`, where `<input>` lists one file path per line.
- Shared structure X (file names): producers pick a random remaining file under a mutex.
- Shared queue Y (bounded to 10 lines): `std::mutex` with `not_full` / `not_empty` condition variables.
- Shared table Z (word counts): an `unordered_map` behind a mutex; output is sorted alphabetically as `WORD COUNT`.
- Termination: the last producer to finish sets `producers_done` and wakes all consumers, which exit once the queue is empty.
- Words are runs of letters, so punctuation is ignored.

`problem3/tests/` has 17 test inputs and `230217_single.cpp`, a single-threaded reference. `run_tests.sh` runs every test with many producer/consumer configurations (including lopsided ones such as 1x16 and 200x200) and compares against the reference.

## Layout
```
assignment1.pdf                problem statement
problem1/cache-miss-analysis.txt   written solution
problem2/                      problem2.cpp, run.sh
problem3/                      230217.cpp, tests/ (inputs, single-threaded reference, run_tests.sh)
Makefile
```

## Build and run
```bash
make                      # or: make problem2 | problem3 (g++ -std=c++17 -O3)
cd problem2 && ./run.sh   # block-size sweep; takes several minutes for N = 2048
cd ../problem3/tests/test1 && ../../230217.out input 4 3   # run inside a test directory
cd ../.. && cd tests && ./run_tests.sh [test1 test5 ...]
```
Input file paths are resolved relative to the working directory, so run each test from inside its directory.

## Test environment
Problem 2 was timed on a CSE lab workstation with nothing else running. Absolute times depend on the machine.

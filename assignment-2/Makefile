# CS 610 Assignment 2 (roll no. 230217)
# Usage: make problem2 | make problem3 | make problem4 | make all | make clean
CC  = gcc
CXX = g++

SIMD_FLAGS = -msse4 -mavx2 -march=native
CXXFLAGS   = -std=c++17 -masm=att $(SIMD_FLAGS) -fopenmp -fno-exceptions -fno-rtti -fcf-protection=none
# gnu17 (not plain c17) so CLOCK_MONOTONIC_RAW is visible
CFLAGS     = -std=gnu17 -O3 -march=native
LIBS       = -pthread -static-libstdc++ -static-libgcc

.PHONY: all problem2 problem3 problem4 clean

all: problem2 problem3 problem4

problem2: problem2/230217-prob2.out
problem3: problem3/230217-prob3.out
problem4: problem4/230217-prob4.out

problem2/230217-prob2.out: problem2/230217-prob2.cpp
	$(CXX) $(CXXFLAGS) -O2 $< -o $@ $(LIBS)

problem3/230217-prob3.out: problem3/230217-prob3.cpp
	$(CXX) $(CXXFLAGS) -O2 $< -o $@ $(LIBS)

# Run from inside problem4/ (reads ./disp.txt and ./grid.txt, writes ./results-v1.txt)
problem4/230217-prob4.out: problem4/230217-prob4.c
	$(CC) $(CFLAGS) $< -o $@ -lm

clean:
	rm -f -- problem2/*.out problem3/*.out problem4/*.out problem4/results-*.txt

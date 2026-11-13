# sm_86 = NVIDIA A40 (gpu3). Change -arch for other GPUs.
NVCC=nvcc
CXX=g++
CUDAFLAGS=-O3 -std=c++17 -arch=sm_86 -lineinfo -res-usage -src-in-ptx

all: 230217-prob2 make_traces

230217-prob2: 230217-prob2.cu
	$(NVCC) $(CUDAFLAGS) $< -o $(patsubst %.cu,%.out,$<)

make_traces: make_traces.cpp
	$(CXX) -O2 -std=c++17 $< -o $@

# ./230217-prob2.out <insert trace> <search trace> [ll|slab|both] [repetitions]
run: 230217-prob2
	./230217-prob2.out traces/insert_keys_values_100k.bin traces/search_keys_100k.bin

clean:
	rm -f *.out make_traces

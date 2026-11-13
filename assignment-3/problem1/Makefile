# sm_86 = NVIDIA A40 (gpu3). Change -arch for other GPUs.
NVCC=nvcc
CUDAFLAGS=-O3 -std=c++17 -arch=sm_86 -lineinfo -res-usage -src-in-ptx

all: 230217-prob1

230217-prob1: 230217-prob1.cu
	$(NVCC) $(CUDAFLAGS) $< -o $(patsubst %.cu,%.out,$<)

# ./230217-prob1.out <number of elements>; 268435456 (2^28) oversubscribes the 2GB GPU
run: 230217-prob1
	./230217-prob1.out 16777216

clean:
	rm -f *.out

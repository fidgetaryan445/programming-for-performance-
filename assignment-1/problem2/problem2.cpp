#include <iostream>
#include <vector>
#include <chrono>
#include <cstdlib>
#include <iomanip>

void mmm_blocked(int *A, int *B, int *C, int N, int BLK) {
    for (int i = 0; i < N; i += BLK)
      for (int j = 0; j < N; j += BLK)
        for (int k = 0; k < N; k += BLK)
          for (int ii = i; ii < i+BLK; ii++)
            for (int jj = j; jj < j+BLK; jj++)
              for (int kk = k; kk < k+BLK; kk++)
                C[ii*N+jj] += A[ii*N+kk]*B[kk*N+jj];
}

void mmm_sequential(int *A, int *B, int *C, int N) {
    for (int i = 0; i < N; i++)
      for (int j = 0; j < N; j++)
        for (int k = 0; k < N; k++)
          C[i*N+j] += A[i*N+k]*B[k*N+j];
}

int main(int argc, char* argv[]) {
    const int BLK = std::atoi(argv[1]);
    const int N = 2048;
    const int RUNS = 5;

    std::vector<int> A(N * N), B(N * N), C(N * N);

    srand(42);
    for (int i = 0; i < N * N; i++) {
        A[i] = rand() % 10;
        B[i] = rand() % 10;
    }
    //one for warm-up , just in case it would affect the results 
    std::fill(C.begin(), C.end(), 0);
    if (BLK <= 0) mmm_sequential(A.data(), B.data(), C.data(), N);
    else mmm_blocked(A.data(), B.data(), C.data(), N, BLK);

    double total = 0.0;
    for (int r = 0; r < RUNS; r++) {
        std::fill(C.begin(), C.end(), 0);
        auto start = std::chrono::high_resolution_clock::now();
        if (BLK <= 0) mmm_sequential(A.data(), B.data(), C.data(), N);
        else mmm_blocked(A.data(), B.data(), C.data(), N, BLK);
        auto end = std::chrono::high_resolution_clock::now();
        total += std::chrono::duration<double>(end - start).count();
        std::cout << total << '\n';
    }
    double mean_time = total / RUNS;

    std::cout << std::fixed << std::setprecision(6) << mean_time << "\n";

    return 0;
}

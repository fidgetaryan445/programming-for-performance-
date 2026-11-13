#include<iostream>
#include<cstdlib>
#include<climits>
#include<x86intrin.h>
#include<chrono>
#include<cassert>


#define N (1<<8)
#define SSE_WIDTH_SIZE (128)
#define AVX_WIDTH_SIZE (256)
int BLK_SIZE = 1 ; 
int MUL_FUNC = 0 ;


int mmm_sse_aligned(int  (*__restrict A)[N], int (*__restrict B)[N], int (*__restrict C)[N]){
  
  A = static_cast<int(*)[N]>(__builtin_assume_aligned(A,32));
  B = static_cast<int(*)[N]>(__builtin_assume_aligned(B,32));
  C = static_cast<int(*)[N]>(__builtin_assume_aligned(C,32));

  for(int i = 0 ; i < N ; i+=BLK_SIZE){
      for(int k = 0 ; k <N ; k+=BLK_SIZE){
        for(int j = 0 ; j<N ; j+=BLK_SIZE){
          for(int ii = i ; ii < i+BLK_SIZE ; ii++){
            for(int kk = k ; kk< k+BLK_SIZE ; kk++){
              int r = A[ii][kk] ;
              int stride = SSE_WIDTH_SIZE /(sizeof(int)*CHAR_BIT);
              for(int jj = j ; jj < j + BLK_SIZE ; jj+=stride){
                  __m128i c = _mm_load_si128(reinterpret_cast<__m128i*>(&C[ii][jj]));
                  __m128i b = _mm_load_si128(reinterpret_cast<__m128i*>(&B[kk][jj]));
                  __m128i a = _mm_set_epi32(r,r,r,r);
                  c = _mm_add_epi32(c, _mm_mullo_epi32(a, b));
                  _mm_store_si128(reinterpret_cast<__m128i*>(&C[ii][jj]), c);
              }
            }
          }
        }
      }
    }
  return 0;
}


int mmm_sse_unaligned(int (*__restrict A)[N], int (*__restrict B)[N], int (*__restrict C)[N]){
  for(int i = 0 ; i < N ; i+=BLK_SIZE){
      for(int k = 0 ; k <N ; k+=BLK_SIZE){
        for(int j = 0 ; j<N ; j+=BLK_SIZE){
          for(int ii = i ; ii < i+BLK_SIZE ; ii++){
            for(int kk = k ; kk< k+BLK_SIZE ; kk++){
              int r = A[ii][kk] ;
              int stride = SSE_WIDTH_SIZE /(sizeof(int)*CHAR_BIT);
              for(int jj = j ; jj < j + BLK_SIZE ; jj+=stride){
                  __m128i c = _mm_loadu_si128(reinterpret_cast<__m128i*>(&C[ii][jj]));
                  __m128i b = _mm_loadu_si128(reinterpret_cast<__m128i*>(&B[kk][jj]));
                  __m128i a = _mm_set_epi32(r,r,r,r);
                  c = _mm_add_epi32(c, _mm_mullo_epi32(a, b));
                  _mm_storeu_si128(reinterpret_cast<__m128i*>(&C[ii][jj]), c);
              }
            }
          }
        }
      }
    }
  return 0;
}

int mmm_avx2_aligned(int (*__restrict A)[N], int (*__restrict B)[N], int (*__restrict C)[N]){

  A = static_cast<int(*)[N]>(__builtin_assume_aligned(A,32));
  B = static_cast<int(*)[N]>(__builtin_assume_aligned(B,32));
  C = static_cast<int(*)[N]>(__builtin_assume_aligned(C,32));

  for(int i = 0 ; i < N ; i+=BLK_SIZE){
      for(int k = 0 ; k <N ; k+=BLK_SIZE){
        for(int j = 0 ; j<N ; j+=BLK_SIZE){
          for(int ii = i ; ii < i+BLK_SIZE ; ii++){
            for(int kk = k ; kk< k+BLK_SIZE ; kk++){
              int r = A[ii][kk] ;
              int stride = AVX_WIDTH_SIZE /(sizeof(int)*CHAR_BIT);
              for(int jj = j ; jj < j + BLK_SIZE ; jj+=stride){
                  __m256i c = _mm256_load_si256(reinterpret_cast<__m256i*>(&C[ii][jj]));
                  __m256i b = _mm256_load_si256(reinterpret_cast<__m256i*>(&B[kk][jj]));
                  __m256i a = _mm256_set1_epi32(r);
                  c = _mm256_add_epi32(c, _mm256_mullo_epi32(a, b));
                  _mm256_store_si256(reinterpret_cast<__m256i*>(&C[ii][jj]), c);
              }
            }
          }
        }
      }
    }
  return 0;
}


int mmm_avx2_unaligned(int (*__restrict A)[N], int (*__restrict B)[N], int (*__restrict C)[N]){
  for(int i = 0 ; i < N ; i+=BLK_SIZE){
      for(int k = 0 ; k <N ; k+=BLK_SIZE){
        for(int j = 0 ; j<N ; j+=BLK_SIZE){
          for(int ii = i ; ii < i+BLK_SIZE ; ii++){
            for(int kk = k ; kk< k+BLK_SIZE ; kk++){
              int r = A[ii][kk] ;
              int stride = AVX_WIDTH_SIZE /(sizeof(int)*CHAR_BIT);
              for(int jj = j ; jj < j + BLK_SIZE ; jj+=stride){
                  __m256i c = _mm256_loadu_si256(reinterpret_cast<__m256i*>(&C[ii][jj]));
                  __m256i b = _mm256_loadu_si256(reinterpret_cast<__m256i*>(&B[kk][jj]));
                  __m256i a = _mm256_set1_epi32(r);
                  c = _mm256_add_epi32(c, _mm256_mullo_epi32(a, b));
                  _mm256_storeu_si256(reinterpret_cast<__m256i*>(&C[ii][jj]), c);
              }
            }
          }
        }
      }
    }
  return 0;
}



using std::cout;
using std::endl;
using HR = std::chrono::high_resolution_clock;
using HRTimer = HR::time_point;
using std::chrono::duration_cast;
using std::chrono::microseconds;

void flush_matrix(void* mat, size_t bytes) {
  constexpr size_t CACHE_LINE = 64;
  char* p = static_cast<char*>(mat);
  for (size_t off = 0; off < bytes; off += CACHE_LINE) {
    _mm_clflush(p + off);
  }
}

static void usage(const char* prog) {
  std::cerr << "Usage: " << prog << " [<BLK_SIZE> <MUL_FUNC>]\n"
            << "  BLK_SIZE: power of two >= 4 (>= 8 for AVX2)\n"
            << "  MUL_FUNC: 0 SSE aligned, 1 SSE unaligned, 2 AVX2 aligned, 3 AVX2 unaligned\n"
            << "  With no arguments, all four variants are run with BLK_SIZE=64.\n";
}

__attribute__((optimize("no-tree-vectorize")))int main (int argc, char *argv[]) {
  int first = 0, last = 3;
  BLK_SIZE = 64;
  if (argc == 3) {
    BLK_SIZE = std::atoi(argv[1]);
    MUL_FUNC = std::atoi(argv[2]);
    if (BLK_SIZE < 4 || __builtin_popcount(BLK_SIZE) != 1 || BLK_SIZE > N ||
        MUL_FUNC < 0 || MUL_FUNC > 3 || (MUL_FUNC >= 2 && BLK_SIZE < 8)) {
      usage(argv[0]);
      return -2;
    }
    first = last = MUL_FUNC;
  } else if (argc != 1) {
    usage(argv[0]);
    return -1;
  }
  alignas(64) static int A[N][N], B[N][N], C[N][N], C_ref[N][N];

  // Copies of A, B, C shifted by one int (4 bytes) so every row is misaligned.
  // Used by the "unaligned" variants.
  alignas(64) static int A_raw[N*N + 16], B_raw[N*N + 16], C_raw[N*N + 16];
  int (*A_u)[N] = reinterpret_cast<int(*)[N]>(A_raw + 1);
  int (*B_u)[N] = reinterpret_cast<int(*)[N]>(B_raw + 1);
  int (*C_u)[N] = reinterpret_cast<int(*)[N]>(C_raw + 1);

  srand(42);
  for (int i = 0; i < N; i++) {
    for (int j = 0; j < N; j++) {
      A[i][j] = rand() % 10;
      B[i][j] = rand() % 10;
    }
  }

  // Serial reference for correctness checking.
  for (int i = 0; i < N; i++) {
    for (int k = 0; k < N; k++) {
      int r = A[i][k];
      for (int j = 0; j < N; j++) {
        C_ref[i][j] += r * B[k][j];
      }
    }
  }

  const char* func_names[] = {"SSE aligned", "SSE unaligned", "AVX2 aligned", "AVX2 unaligned"};

  for (MUL_FUNC = first; MUL_FUNC <= last; MUL_FUNC++) {
    bool unaligned = (MUL_FUNC == 1 || MUL_FUNC == 3);
    int (*Cres)[N] = unaligned ? C_u : C;   // matrix holding this run's result

    for (int i = 0; i < N; i++)
      for (int j = 0; j < N; j++) {
        C[i][j] = 0;
        A_u[i][j] = A[i][j];
        B_u[i][j] = B[i][j];
        C_u[i][j] = 0;
      }

    // Evict the matrices from cache so the timed call starts cold.
    flush_matrix(A, sizeof(A));
    flush_matrix(B, sizeof(B));
    flush_matrix(C, sizeof(C));
    flush_matrix(A_raw, sizeof(A_raw));
    flush_matrix(B_raw, sizeof(B_raw));
    flush_matrix(C_raw, sizeof(C_raw));
    _mm_mfence();

    HRTimer start = HR::now();
    switch (MUL_FUNC) {
      case 0: mmm_sse_aligned(A, B, C); break;
      case 1: mmm_sse_unaligned(A_u, B_u, C_u); break;
      case 2: mmm_avx2_aligned(A, B, C); break;
      case 3: mmm_avx2_unaligned(A_u, B_u, C_u); break;
    }
    HRTimer end = HR::now();
    auto duration = duration_cast<microseconds>(end - start).count();

    for (int i = 0; i < N; i++) {
      for (int j = 0; j < N; j++) {
        if (Cres[i][j] != C_ref[i][j]) {
          std::cerr << func_names[MUL_FUNC] << ": WRONG RESULT at (" << i << "," << j << ")\n";
          return 1;
        }
      }
    }

    cout << func_names[MUL_FUNC] << " (N=" << N << ", BLK_SIZE=" << BLK_SIZE
         << "): time: " << duration << " us" << endl;
  }

  return 0;
}

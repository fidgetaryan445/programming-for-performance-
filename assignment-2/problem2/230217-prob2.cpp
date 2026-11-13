#include <algorithm>
#include <cassert>
#include <chrono>
#include <climits>
#include <cstdlib>
#include <iostream>
#include <x86intrin.h>

using std::cout;
using std::endl;
using std::chrono::duration_cast;
using HR = std::chrono::high_resolution_clock;
using HRTimer = HR::time_point;
using std::chrono::microseconds;

#define N (1 << 16)
#define SSE_WIDTH_BITS (128)
#define AVX_WIDTH_BITS (256)
#define ALIGN (32)

/** Helper methods for debugging */

void print_array(const int* array) {
  for (int i = 0; i < N; i++) {
    cout << array[i] << "\t";
  }
  cout << "\n";
}

void print128i_u32(__m128i var, int start) {
  alignas(ALIGN) uint32_t val[4];
  _mm_store_si128(reinterpret_cast<__m128i*>(val), var);
  cout << "Values [" << start << ":" << start + 3 << "]: " << val[0] << " "
       << val[1] << " " << val[2] << " " << val[3] << "\n";
}

void print128i_u64(__m128i var) {
  alignas(ALIGN) uint64_t val[2];
  _mm_store_si128(reinterpret_cast<__m128i*>(val), var);
  cout << "Values [0:1]: " << val[0] << " " << val[1] << "\n";
}

__attribute__((optimize("no-tree-vectorize"))) int
ref_version(int* __restrict__ source, int* __restrict__ dest) {
  source = static_cast<int*>(__builtin_assume_aligned(source, ALIGN));
  dest = static_cast<int*>(__builtin_assume_aligned(dest, ALIGN));

  int tmp = 0;
  for (int i = 0; i < N; i++) {
    dest[i] = tmp;
    tmp += source[i];
  }
  return tmp;
}

int sse4_version(const int* __restrict__ source, int* __restrict__ dest) { 
  source = static_cast<int*>(__builtin_assume_aligned(source,ALIGN));
  dest = static_cast<int*>(__builtin_assume_aligned(dest,ALIGN));

  __m128i offset = _mm_setzero_si128();

    const int stride = SSE_WIDTH_BITS / (sizeof(int)*CHAR_BIT) ;
    for(int i = 0 ; i < N  ; i+=stride){
      __m128i x = _mm_load_si128(reinterpret_cast<const __m128i*>(&source[i]));

      __m128i tmp0 = _mm_slli_si128(x,4) ;
      __m128i tmp1 = _mm_add_epi32(x,tmp0);
      __m128i tmp2 = _mm_slli_si128(tmp1,8);
      __m128i out  = _mm_add_epi32(tmp2,tmp1);
      out = _mm_add_epi32(out,offset);
     // _mm_store_si128(reinterpret_cast<__m128i*>(&dest[i]),out);
      offset = _mm_shuffle_epi32(out, 255);
      out = _mm_sub_epi32(out,x);
      _mm_store_si128(reinterpret_cast<__m128i*>(&dest[i]),out);
    }

  return _mm_extract_epi32(offset, 3);
}

int avx2_version(const int* __restrict__ source, int* __restrict__ dest) {
  source = static_cast<int*>(__builtin_assume_aligned(source,ALIGN));
  dest   = static_cast<int*>(__builtin_assume_aligned(dest,ALIGN)) ; 

  __m256i offset = _mm256_setzero_si256();
  int stride = AVX_WIDTH_BITS /(sizeof(int)*CHAR_BIT);

  for(int i = 0 ; i < N ; i+=stride){
    __m256i x = _mm256_load_si256(reinterpret_cast<const __m256i*>(&source[i]));
    __m256i tmp0 = _mm256_slli_si256(x,4);
    __m256i tmp1 = _mm256_add_epi32(tmp0,x);
    __m256i tmp2 = _mm256_slli_si256(tmp1,8);
    __m256i out  = _mm256_add_epi32(tmp2, tmp1);
   // __m256i label= _mm256_permute2x128_si256(out,out,0);
   //__m256i upper_lane_offset  = _mm256_blend_epi32(_mm256_setzero_si256(),label,0b11110000);
   // out = _mm256_add_epi32(out,upper_lane_offset);
    __m256i upper_lane_offset = _mm256_permute2x128_si256(out, out, 0x08);
    upper_lane_offset = _mm256_shuffle_epi32(upper_lane_offset, 0xFF);
    out = _mm256_add_epi32(out, upper_lane_offset);
    out = _mm256_add_epi32(out,offset);
    offset = _mm256_shuffle_epi32( _mm256_permute2x128_si256(out,out,17),255);
    out = _mm256_sub_epi32(out,x);
    _mm256_store_si256(reinterpret_cast<__m256i*>(&dest[i]),out);

  }

  return _mm256_extract_epi32(offset, 7); }

__attribute__((optimize("no-tree-vectorize"))) int main() {
  int* array = static_cast<int*>(aligned_alloc(ALIGN, N * sizeof(int)));
  std::fill(array, array + N, 1);

  int* ref_res = static_cast<int*>(aligned_alloc(ALIGN, N * sizeof(int)));
  std::fill(ref_res, ref_res + N, 0);
  HRTimer start = HR::now();
  int val_ser = ref_version(array, ref_res);
  HRTimer end = HR::now();
  auto duration = duration_cast<microseconds>(end - start).count();
  cout << "Serial version: " << val_ser << " time: " << duration << endl;

   int* sse_res = static_cast<int*>(aligned_alloc(ALIGN, N * sizeof(int)));
   std::fill(sse_res, sse_res + N, 0);
   start = HR::now();
   int val_sse = sse4_version(array, sse_res);
   end = HR::now();
   duration = duration_cast<microseconds>(end - start).count();
   assert(val_ser == val_sse || printf("SSE result is wrong!\n"));
   cout << "SSE version: " << val_sse << " time: " << duration << endl;
   free(sse_res);

   int* avx2_res = static_cast<int*>(aligned_alloc(ALIGN, N * sizeof(int)));
   std::fill(avx2_res, avx2_res + N, 0);
   start = HR::now();
   int val_avx2 = avx2_version(array, avx2_res);
   end = HR::now();
   duration = duration_cast<microseconds>(end - start).count();
   assert(val_ser == val_avx2 || printf("AVX2 result is wrong!\n"));
   cout << "AVX2 version: " << val_avx2 << " time: " << duration << endl;
   free(avx2_res);

  free(array);
  free(ref_res);
  return EXIT_SUCCESS;
}

#include <cassert>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <cuda.h>
#include <iostream>
#include <random>
#include <vector>

using std::cerr;
using std::cout;
using std::endl;

using std::chrono::duration_cast;
using HR = std::chrono::high_resolution_clock;
using HRTimer = HR::time_point;
using std::chrono::microseconds;
using std::chrono::milliseconds;

typedef uint64_t u64;

u64 N = (1 << 24);

const u64 GPU_MEM = 2ull << 30;
const u64 TILE = 1024;
const u64 CHUNK = 1 << 25;
const int NS = 3;

#define cudaCheckError(ans)                                                    \
  do {                                                                         \
    gpuAssert((ans), __FILE__, __LINE__);                                      \
  } while (0)
inline void gpuAssert(cudaError_t code, const char* file, int line,
                      bool abort = true) {
  if (code != cudaSuccess) {
    fprintf(stderr, "GPUassert: %s %s %d\n", cudaGetErrorString(code), file,
            line);
    if (abort)
      exit(code);
  }
}

__global__ void cte_sum_basic(const u64* in, u64* out, u64* sums, u64 n) {
  __shared__ u64 s[1024];
  u64 i = blockIdx.x * 1024ull + threadIdx.x;
  int t = threadIdx.x;
  s[t] = (i < n) ? in[i] : 0;
  for (int d = 1; d < 1024; d <<= 1) {
    __syncthreads();
    u64 v = (t >= d) ? s[t - d] : 0;
    __syncthreads();
    s[t] += v;
  }
  __syncthreads();
  if (i < n)
    out[i] = s[t];
  if (t == 1023)
    sums[blockIdx.x] = s[t];
}

__global__ void cte_sum_opt(const u64* in, u64* out, u64* sums, u64 n) {
  __shared__ u64 w[8];
  int t = threadIdx.x, lane = t & 31, wid = t >> 5;
  u64 base = blockIdx.x * 1024ull + t * 4, r[4], s = 0;
  for (int j = 0; j < 4; j++) {
    s += (base + j < n) ? in[base + j] : 0;
    r[j] = s;
  }
  u64 v = s;
  for (int d = 1; d < 32; d <<= 1) {
    u64 x = __shfl_up_sync(~0u, v, d);
    if (lane >= d)
      v += x;
  }
  if (lane == 31)
    w[wid] = v;
  __syncthreads();
  if (wid == 0) {
    u64 x = (lane < 8) ? w[lane] : 0;
    for (int d = 1; d < 8; d <<= 1) {
      u64 y = __shfl_up_sync(~0u, x, d);
      if (lane >= d)
        x += y;
    }
    if (lane < 8)
      w[lane] = x;
  }
  __syncthreads();
  u64 off = v - s + (wid ? w[wid - 1] : 0);
  for (int j = 0; j < 4; j++)
    if (base + j < n)
      out[base + j] = r[j] + off;
  if (t == 255)
    sums[blockIdx.x] = w[7];
}

__global__ void scan_sums(u64* sums, u64 nb, u64* carry) {
  __shared__ u64 s[1024];
  int t = threadIdx.x;
  u64 per = (nb + 1023) / 1024, lo = t * per, hi = min(lo + per, nb), a = 0;
  for (u64 i = lo; i < hi; i++)
    a += sums[i];
  s[t] = a;
  __syncthreads();
  if (t == 0) {
    u64 r = *carry;
    for (int i = 0; i < 1024; i++) {
      u64 x = s[i];
      s[i] = r;
      r += x;
    }
    *carry = r;
  }
  __syncthreads();
  u64 r = s[t];
  for (u64 i = lo; i < hi; i++) {
    u64 x = sums[i];
    sums[i] = r;
    r += x;
  }
}

__global__ void add_offsets(u64* out, const u64* sums, u64 n) {
  u64 i = blockIdx.x * 1024ull + threadIdx.x;
  if (i < n)
    out[i] += sums[blockIdx.x];
}

static void scan_dev(const u64* in, u64* out, u64 m, u64* sums, u64* carry,
                     cudaStream_t s, bool opt, cudaEvent_t wait = nullptr,
                     cudaEvent_t done = nullptr) {
  u64 nb = (m + TILE - 1) / TILE;
  if (opt)
    cte_sum_opt<<<nb, 256, 0, s>>>(in, out, sums, m);
  else
    cte_sum_basic<<<nb, 1024, 0, s>>>(in, out, sums, m);
  if (wait)
    cudaCheckError(cudaStreamWaitEvent(s, wait, 0));
  scan_sums<<<1, 1024, 0, s>>>(sums, nb, carry);
  if (done)
    cudaCheckError(cudaEventRecord(done, s));
  add_offsets<<<nb, 1024, 0, s>>>(out, sums, m);
  cudaCheckError(cudaGetLastError());
}

__host__ void generate_random(u64* a, const u64 size) {
  std::mt19937_64 gen(610);
  for (u64 i = 0; i < size; i++)
    a[i] = gen() & 0xFFFFFFFFull;
}

__host__ void check_result(const u64* w_ref, const u64* w_opt,
                           const u64 size) {
  for (u64 i = 0; i < size; i++) {
    if (w_ref[i] != w_opt[i]) {
      cout << "Differences found between the two arrays.\n";
      assert(false);
    }
  }
  cout << "No differences found between base and test versions\n";
}

__host__ void inclusive_prefix_sum(const u64* input, u64* output) {
  output[0] = input[0];
  for (u64 i = 1; i < N; i++) {
    output[i] = output[i - 1] + input[i];
  }
}

static double ms_since(HRTimer t0) {
  return duration_cast<microseconds>(HR::now() - t0).count() / 1000.0;
}

static volatile u64 sink;
static void touch(const u64* a) {
  u64 x = 0;
  for (u64 i = 0; i < N; i += 512)
    x += a[i];
  sink = x;
}

static double cte_basic(const u64* h_in, u64* h_out) {
  u64 *d_in, *d_out, *d_sums, *d_carry, nb = N / TILE + 1;
  cudaCheckError(cudaMalloc(&d_in, N * 8));
  cudaCheckError(cudaMalloc(&d_out, N * 8));
  cudaCheckError(cudaMalloc(&d_sums, nb * 8));
  cudaCheckError(cudaMalloc(&d_carry, 8));
  cudaCheckError(cudaMemset(d_carry, 0, 8));
  HRTimer t0 = HR::now();
  cudaCheckError(cudaMemcpy(d_in, h_in, N * 8, cudaMemcpyHostToDevice));
  scan_dev(d_in, d_out, N, d_sums, d_carry, 0, false);
  cudaCheckError(cudaMemcpy(h_out, d_out, N * 8, cudaMemcpyDeviceToHost));
  double ms = ms_since(t0);
  cudaFree(d_in);
  cudaFree(d_out);
  cudaFree(d_sums);
  cudaFree(d_carry);
  return ms;
}

static double batched(const u64* h_in, u64* h_out, bool uvm) {
  u64 chunk = std::min(CHUNK, N), nbatch = (N + chunk - 1) / chunk;
  cudaStream_t st[NS];
  u64 *d_buf[NS], *d_sums[NS], *d_carry;
  std::vector<cudaEvent_t> ev(nbatch);
  for (int k = 0; k < NS; k++) {
    cudaCheckError(cudaStreamCreate(&st[k]));
    cudaCheckError(cudaMalloc(&d_sums[k], (chunk / TILE + 1) * 8));
    if (!uvm)
      cudaCheckError(cudaMalloc(&d_buf[k], chunk * 8));
  }
  for (auto& e : ev)
    cudaCheckError(cudaEventCreateWithFlags(&e, cudaEventDisableTiming));
  cudaCheckError(cudaMalloc(&d_carry, 8));
  cudaCheckError(cudaMemset(d_carry, 0, 8));
  cudaCheckError(cudaDeviceSynchronize());

  HRTimer t0 = HR::now();
  for (u64 b = 0; b < nbatch; b++) {
    int k = b % NS;
    u64 off = b * chunk, m = std::min(chunk, N - off);
    u64* buf = uvm ? h_out + off : d_buf[k];
    if (uvm)
      cudaCheckError(cudaMemPrefetchAsync(buf, m * 8, 0, st[k]));
    else
      cudaCheckError(cudaMemcpyAsync(buf, h_in + off, m * 8,
                                     cudaMemcpyHostToDevice, st[k]));
    scan_dev(buf, buf, m, d_sums[k], d_carry, st[k], true,
             b ? ev[b - 1] : nullptr, ev[b]);
    if (uvm)
      cudaCheckError(cudaMemPrefetchAsync(buf, m * 8, cudaCpuDeviceId, st[k]));
    else
      cudaCheckError(cudaMemcpyAsync(h_out + off, buf, m * 8,
                                     cudaMemcpyDeviceToHost, st[k]));
  }
  cudaCheckError(cudaDeviceSynchronize());
  if (uvm)
    touch(h_out);
  double ms = ms_since(t0);

  return ms;
}

int main(int argc, char** argv) {
  if (argc > 1)
    N = strtoull(argv[1], nullptr, 10);

  size_t free_b, total_b;
  void* hog;
  cudaCheckError(cudaFree(0));
  cudaMemGetInfo(&free_b, &total_b);
  cudaCheckError(cudaMalloc(&hog, free_b - GPU_MEM));

  auto* h_input = new u64[N];
  generate_random(h_input, N);

  auto* h_output_cpu = new u64[N];
  inclusive_prefix_sum(h_input, h_output_cpu);

  auto* h_output = new u64[N]();

  // TODO: Use a basic CUDA kernel with CTE, time your code
  if (2 * N * 8 + 8 * (N / TILE + 1) > GPU_MEM) {
    cout << "CTE basic: input does not fit in the GPU memory, skipped\n";
  } else {
    cout << "CTE basic: " << cte_basic(h_input, h_output) << " ms\n";
    check_result(h_output_cpu, h_output, N);
  }

  // TODO: Use an optimized CUDA kernel with CTE, time your code. It is okay if you want to move this implementation to a separate file.
  u64 *h_pin_in, *h_pin_out;
  cudaCheckError(cudaMallocHost(&h_pin_in, N * 8));
  cudaCheckError(cudaMallocHost(&h_pin_out, N * 8));
  memcpy(h_pin_in, h_input, N * 8);
  cout << "CTE opt: " << batched(h_pin_in, h_pin_out, false) << " ms\n";
  check_result(h_output_cpu, h_pin_out, N);
  cudaFreeHost(h_pin_in);
  cudaFreeHost(h_pin_out);

  // TODO: Use a basic CUDA kernel with UVM, time your code
  {
    u64 *in, *out, *sums, *carry;
    cudaCheckError(cudaMallocManaged(&in, N * 8));
    cudaCheckError(cudaMallocManaged(&out, N * 8));
    cudaCheckError(cudaMalloc(&sums, (N / TILE + 1) * 8));
    cudaCheckError(cudaMalloc(&carry, 8));
    cudaCheckError(cudaMemset(carry, 0, 8));
    memcpy(in, h_input, N * 8);
    HRTimer t0 = HR::now();
    scan_dev(in, out, N, sums, carry, 0, false);
    cudaCheckError(cudaDeviceSynchronize());
    touch(out);
    cout << "UVM basic: " << ms_since(t0) << " ms\n";
    check_result(h_output_cpu, out, N);
    cudaFree(in);
    cudaFree(out);
    cudaFree(sums);
    cudaFree(carry);
  }

  // TODO: Use an optimized CUDA kernel with UVM, time your code. It is okay if you want to move this implementation to a separate file.
  {
    u64* um;
    cudaCheckError(cudaMallocManaged(&um, N * 8));
    memcpy(um, h_input, N * 8);
    cout << "UVM opt: " << batched(um, um, true) << " ms\n";
    check_result(h_output_cpu, um, N);
    cudaFree(um);
  }

  delete[] h_input;
  delete[] h_output_cpu;
  delete[] h_output;
  cudaFree(hog);

  return EXIT_SUCCESS;
}

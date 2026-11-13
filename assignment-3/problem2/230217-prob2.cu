#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>
#include <iostream>
#include <string>
#include <unordered_map>
#include <vector>

using std::cout;
using std::vector;
typedef uint32_t u32;
typedef unsigned long long u64;

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

const u32 B = 3000;
const u32 MAX_KEYS = 100000;
const u32 NIL = 0xFFFFFFFFu;
const u32 BLOCK = 128;
const u32 LL_POOL = B + MAX_KEYS;
const u32 SLAB_POOL = B + 2 * (MAX_KEYS / 15) + 8192;

__device__ __forceinline__ u32 hash_key(u32 k) {
  return (u32)(((2654435769ull * k + 40503ull) % 4294967291ull) % B);
}

// ---------------- linked list: nodes[0..B) are the bucket heads ----------------
struct Node {
  u32 key, value, next, pad;
};

__global__ void ll_init(Node* nodes) {
  u32 i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < LL_POOL)
    nodes[i] = Node{0, 0, NIL, 0};
}

__global__ void ll_insert(Node* nodes, u32* ctr, const u32* keys,
                          const u32* vals, u32 n) {
  u32 t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n || keys[t] == 0)
    return;
  u32 h = hash_key(keys[t]);
  u32 idx = B + atomicAdd(ctr, 1u);
  if (idx >= LL_POOL)
    return;
  nodes[idx].key = keys[t];
  nodes[idx].value = vals[t];
  u32 old = __ldcg(&nodes[h].next);
  while (true) {
    nodes[idx].next = old;
    __threadfence();
    u32 prev = atomicCAS(&nodes[h].next, old, idx);
    if (prev == old)
      break;
    old = prev;
  }
}

__global__ void ll_search(const Node* nodes, const u32* keys, u32* out, u32 n) {
  u32 t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n)
    return;
  u32 k = keys[t], res = 0;
  u32 cur = (k != 0) ? nodes[hash_key(k)].next : NIL;
  while (cur != NIL) {
    uint4 nd = *reinterpret_cast<const uint4*>(&nodes[cur]);
    if (nd.x == k) {
      res = nd.y;
      break;
    }
    cur = nd.z;
  }
  out[t] = res;
}

// ---------------- slab list: slab = 32 words, 15 (key,value) pairs + next ------
__global__ void slab_init(u32* slabs) {
  u32 i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < SLAB_POOL * 32)
    slabs[i] = ((i & 31) == 31) ? NIL : 0u;
}

__global__ void slab_insert(u32* slabs, u32* ctr, const u32* keys,
                            const u32* vals, u32 n) {
  u32 t = blockIdx.x * blockDim.x + threadIdx.x;
  int lane = threadIdx.x & 31;
  u32 key = (t < n) ? keys[t] : 0, val = (t < n) ? vals[t] : 0;
  bool work = key != 0;
  while (u32 q = __ballot_sync(~0u, work)) {
    int src = __ffs(q) - 1;
    u32 skey = __shfl_sync(~0u, key, src), sval = __shfl_sync(~0u, val, src);
    u32 cur = hash_key(skey);
    bool done = false;
    while (!done) {
      u32 w = __ldcg(&slabs[cur * 32 + lane]);
      u32 empty = __ballot_sync(~0u, lane < 30 && !(lane & 1) && w == 0);
      if (empty) {
        int l = __ffs(empty) - 1;
        bool ok = false;
        if (lane == l)
          ok = atomicCAS((u64*)&slabs[cur * 32 + l], 0ull,
                         (u64)skey | ((u64)sval << 32)) == 0ull;
        done = __shfl_sync(~0u, (int)ok, l);
      } else {
        u32 nxt = __shfl_sync(~0u, w, 31);
        if (nxt != NIL) {
          cur = nxt;
        } else {
          u32 np = __shfl_sync(~0u, lane == 0 ? B + atomicAdd(ctr, 1u) : 0, 0);
          if (np >= SLAB_POOL)
            break;
          u32 old = 0;
          if (lane == 31)
            old = atomicCAS(&slabs[cur * 32 + 31], NIL, np);
          old = __shfl_sync(~0u, old, 31);
          cur = (old == NIL) ? np : old;
        }
      }
    }
    if (lane == src)
      work = false;
  }
}

__global__ void slab_search(const u32* slabs, const u32* keys, u32* out,
                            u32 n) {
  u32 t = blockIdx.x * blockDim.x + threadIdx.x;
  int lane = threadIdx.x & 31;
  u32 key = (t < n) ? keys[t] : 0;
  bool work = key != 0;
  if (t < n && !work)
    out[t] = 0;
  while (u32 q = __ballot_sync(~0u, work)) {
    int src = __ffs(q) - 1;
    u32 skey = __shfl_sync(~0u, key, src), cur = hash_key(skey), res = 0;
    while (true) {
      u32 w = slabs[cur * 32 + lane];
      u32 m = __ballot_sync(~0u, lane < 30 && !(lane & 1) && w == skey);
      if (m) {
        res = __shfl_sync(~0u, w, __ffs(m));
        break;
      }
      cur = __shfl_sync(~0u, w, 31);
      if (cur == NIL)
        break;
    }
    if (lane == src) {
      out[t] = res;
      work = false;
    }
  }
}

// ---------------- host ----------------
void* d_tab;
u32 *d_ctr, *d_keys, *d_vals, *d_out;
cudaEvent_t e0, e1;

void init_table(bool slab) {
  cudaCheckError(cudaMemset(d_ctr, 0, 4));
  if (slab)
    slab_init<<<(SLAB_POOL * 32 + 255) / 256, 256>>>((u32*)d_tab);
  else
    ll_init<<<(LL_POOL + 255) / 256, 256>>>((Node*)d_tab);
  cudaCheckError(cudaDeviceSynchronize());
}

float insert_host(bool slab, const vector<u32>& k, const vector<u32>& v) {
  u32 n = k.size(), threads = (n + 31) / 32 * 32;
  cudaCheckError(cudaMemcpy(d_keys, k.data(), n * 4, cudaMemcpyHostToDevice));
  cudaCheckError(cudaMemcpy(d_vals, v.data(), n * 4, cudaMemcpyHostToDevice));
  cudaEventRecord(e0);
  if (slab)
    slab_insert<<<(threads + BLOCK - 1) / BLOCK, BLOCK>>>(
        (u32*)d_tab, d_ctr, d_keys, d_vals, n);
  else
    ll_insert<<<(n + BLOCK - 1) / BLOCK, BLOCK>>>((Node*)d_tab, d_ctr, d_keys,
                                                  d_vals, n);
  cudaEventRecord(e1);
  cudaCheckError(cudaEventSynchronize(e1));
  float ms;
  cudaEventElapsedTime(&ms, e0, e1);
  return ms;
}

float search_host(bool slab, const vector<u32>& k, vector<u32>& out) {
  u32 n = k.size();
  out.resize(n);
  cudaCheckError(cudaMemcpy(d_keys, k.data(), n * 4, cudaMemcpyHostToDevice));
  cudaEventRecord(e0);
  if (slab)
    slab_search<<<(n + BLOCK - 1) / BLOCK, BLOCK>>>((u32*)d_tab, d_keys, d_out,
                                                    n);
  else
    ll_search<<<(n + BLOCK - 1) / BLOCK, BLOCK>>>((Node*)d_tab, d_keys, d_out,
                                                  n);
  cudaEventRecord(e1);
  cudaCheckError(cudaEventSynchronize(e1));
  float ms;
  cudaEventElapsedTime(&ms, e0, e1);
  cudaCheckError(cudaMemcpy(out.data(), d_out, n * 4, cudaMemcpyDeviceToHost));
  return ms;
}

bool check_result(const vector<u32>& ik, const vector<u32>& iv,
                  const vector<u32>& sk, const vector<u32>& gpu) {
  std::unordered_map<u32, u32> ref;
  for (size_t i = 0; i < ik.size(); i++)
    ref[ik[i]] = iv[i];
  size_t bad = 0;
  for (size_t i = 0; i < sk.size(); i++) {
    auto it = ref.find(sk[i]);
    bad += gpu[i] != (it == ref.end() ? 0 : it->second);
  }
  cout << (bad ? "FAILED" : "PASSED") << " (" << bad << " mismatches)\n";
  return bad == 0;
}

vector<u32> read_file(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f) {
    perror(path);
    exit(1);
  }
  fseek(f, 0, SEEK_END);
  vector<u32> v(ftell(f) / 4);
  fseek(f, 0, SEEK_SET);
  if (fread(v.data(), 4, v.size(), f) != v.size())
    exit(1);
  fclose(f);
  return v;
}

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s insert.bin search.bin [ll|slab|both] [reps]\n",
            argv[0]);
    return 1;
  }
  std::string which = argc > 3 ? argv[3] : "both";
  int reps = argc > 4 ? atoi(argv[4]) : 2;
  vector<u32> ins = read_file(argv[1]), sk = read_file(argv[2]), ik, iv;
  for (size_t i = 0; i + 1 < ins.size(); i += 2) {
    ik.push_back(ins[i]);
    iv.push_back(ins[i + 1]);
  }
  assert(ik.size() <= MAX_KEYS && sk.size() <= MAX_KEYS);

  cudaCheckError(cudaMalloc(&d_tab, (size_t)SLAB_POOL * 128));
  cudaCheckError(cudaMalloc(&d_ctr, 4));
  cudaCheckError(cudaMalloc(&d_keys, MAX_KEYS * 4));
  cudaCheckError(cudaMalloc(&d_vals, MAX_KEYS * 4));
  cudaCheckError(cudaMalloc(&d_out, MAX_KEYS * 4));
  cudaEventCreate(&e0);
  cudaEventCreate(&e1);

  bool ok = true;
  for (int slab = 0; slab < 2; slab++) {
    if ((which == "ll" && slab) || (which == "slab" && !slab))
      continue;
    float ti = 0, ts = 0;
    vector<u32> out;
    for (int r = 0; r < reps; r++) {
      init_table(slab);
      ti = insert_host(slab, ik, iv);
      ts = search_host(slab, sk, out);
    }
    cout << (slab ? "slab list" : "linked list") << ": insert " << ti
         << " ms, search " << ts << " ms, check_result ";
    ok &= check_result(ik, iv, sk, out);
  }
  return ok ? 0 : 2;
}

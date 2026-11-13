// Generates binary traces: insert trace (interleaved key,value, unique keys) and
// search trace (keys only; ~50% hits, ~50% misses).
// Usage: ./make_traces <n_insert> <n_search> <insert.bin> <search.bin> [seed]
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <unordered_set>
#include <vector>
int main(int argc, char** argv) {
  if (argc < 5) { fprintf(stderr, "usage: %s n_insert n_search insert.bin search.bin [seed]\n", argv[0]); return 1; }
  size_t ni = strtoull(argv[1], 0, 10), ns = strtoull(argv[2], 0, 10);
  std::mt19937 g(argc > 5 ? atoi(argv[5]) : 610);
  auto rnd = [&]() { uint32_t x; do { x = g(); } while (x == 0); return x; }; // keys in [1, 2^32-1]
  std::unordered_set<uint32_t> seen;
  std::vector<uint32_t> keys, ins;
  while (keys.size() < ni) { uint32_t k = rnd(); if (seen.insert(k).second) { keys.push_back(k); ins.push_back(k); ins.push_back(rnd()); } }
  std::vector<uint32_t> srch;
  for (size_t i = 0; i < ns; i++) srch.push_back((i % 2 == 0 && ni) ? keys[g() % ni] : rnd());
  FILE* f = fopen(argv[3], "wb"); fwrite(ins.data(), 4, ins.size(), f); fclose(f);
  f = fopen(argv[4], "wb"); fwrite(srch.data(), 4, srch.size(), f); fclose(f);
  return 0;
}

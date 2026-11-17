// C++ side of the benchmark. extern "C" disables C++ name mangling so Dart's
// @Native can find the symbols. The algorithms match lib/bench/dart_bench.dart
// and rust/src/lib.rs step for step.
#include <algorithm>
#include <cstdint>
#include <vector>

#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif

static int64_t fib(int64_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

// 1. Recursive Fibonacci: function-call overhead.
EXPORT int64_t cpp_fib(int64_t n) { return fib(n); }

// 2. Sieve of Eratosthenes: count primes below n (memory and loops).
EXPORT int64_t cpp_sieve(int64_t n) {
  std::vector<uint8_t> composite(static_cast<size_t>(n), 0);
  int64_t count = 0;
  for (int64_t i = 2; i < n; i++) {
    if (!composite[i]) {
      count++;
      for (int64_t j = i * i; j < n; j += i) composite[j] = 1;
    }
  }
  return count;
}

// 3. Mandelbrot set on a size x size grid, max 500 iterations (floating point).
EXPORT int64_t cpp_mandelbrot(int64_t size) {
  const int maxIter = 500;
  int64_t total = 0;
  for (int64_t py = 0; py < size; py++) {
    for (int64_t px = 0; px < size; px++) {
      double x0 = -2.0 + 2.5 * (double)px / (double)size;
      double y0 = -1.25 + 2.5 * (double)py / (double)size;
      double x = 0.0, y = 0.0;
      int i = 0;
      while (x * x + y * y <= 4.0 && i < maxIter) {
        double xt = x * x - y * y + x0;
        y = 2.0 * x * y + y0;
        x = xt;
        i++;
      }
      total += i;
    }
  }
  return total;
}

// 4. Generate n pseudo-random ints (xorshift32), sort them, return a checksum.
EXPORT int64_t cpp_sort(int64_t n) {
  std::vector<int32_t> v;
  v.reserve(static_cast<size_t>(n));
  uint32_t x = 2463534242u;
  for (int64_t i = 0; i < n; i++) {
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    v.push_back(static_cast<int32_t>(x));
  }
  std::sort(v.begin(), v.end());
  int64_t sum = 0;
  for (int64_t i = 0; i < n; i++) sum += (int64_t)v[i] * (i & 7);
  return sum;
}

// 5. Tiny function used to measure the cost of a single Dart -> C++ call.
EXPORT int64_t cpp_add(int64_t a, int64_t b) {
  return (int64_t)((uint64_t)a + (uint64_t)b);
}

// Identical scalar algorithms compiled separately as C and C++.
// No fast-math, intrinsics, threads, or third-party libraries.
#include <stdint.h>
#if defined(_WIN32)
#define LAB_EXPORT __declspec(dllexport)
#else
#define LAB_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif

LAB_EXPORT void LAB_BLUR(const uint8_t *src, uint8_t *out, int64_t side,
                         int64_t radius) {
  const int64_t diameter = radius * 2 + 1;
  for (int64_t y = radius; y < side - radius; ++y) {
    for (int64_t x = radius; x < side - radius; ++x) {
      uint32_t sum = 0;
      for (int64_t dy = -radius; dy <= radius; ++dy) {
        for (int64_t dx = -radius; dx <= radius; ++dx) {
          sum += src[(y + dy) * side + x + dx];
        }
      }
      out[y * side + x] = (uint8_t)(sum / (diameter * diameter));
    }
  }
}

LAB_EXPORT void LAB_FRACTAL(const uint8_t *src, uint8_t *out, int64_t side,
                            int64_t max_iter) {
  (void)src;
  for (int64_t py = 0; py < side; ++py) {
    for (int64_t px = 0; px < side; ++px) {
      double x0 = -2.0 + 2.5 * (double)px / (double)side;
      double y0 = -1.25 + 2.5 * (double)py / (double)side;
      double x = 0.0, y = 0.0;
      int64_t i = 0;
      while (x * x + y * y <= 4.0 && i < max_iter) {
        double xt = x * x - y * y + x0;
        y = 2.0 * x * y + y0;
        x = xt;
        ++i;
      }
      out[py * side + px] = (uint8_t)(i % 256);
    }
  }
}
#ifdef __cplusplus
}
#endif

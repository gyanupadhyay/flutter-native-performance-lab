# Connected-phone results

Measured on 17 November 2026, around 21:28 IST, on the connected **CPH2467**, Android 15, ARM64, 90 Hz display. Release AOT build: Flutter 3.50.0 / Dart 3.14.0. Image dimensions: **512 x 512**. Kernels use one CPU thread. Battery temperature was approximately 30.6–31.0 C during the repeat.

## Compute comparison

Median milliseconds from seven samples, after two warm-ups per engine. Lower is better. Every output byte matched across all four engines.

| Workload | Dart | Rust | C++ | C |
| --- | ---: | ---: | ---: | ---: |
| 11 x 11 image blur | 39.374 | 31.628 | 18.027 | 18.055 |
| Mandelbrot, 400 iterations | 150.075 | 107.902 | 108.032 | 107.971 |

On this device and implementation, C/C++ were about **2.18x** as fast as Dart for the blur, and Rust about **1.25x**. The three native versions were about **1.39x** as fast as Dart for Mandelbrot. This is not a general ranking of languages; the compiler, algorithm, data representation and device matter.

## Animation while computing

These are Flutter animation-ticker rates, not measured GPU presentation rates. Each capture lasts roughly three seconds. The idle baselines were about 89.8 ticks/sec.

| Workload / execution | Dart | Rust | C++ | C |
| --- | ---: | ---: | ---: | ---: |
| Blur / UI thread | 24.7 | 30.6 | 52.1 | 52.1 |
| Blur / worker | 89.7 | 89.9 | 89.7 | 89.8 |
| Mandelbrot / UI thread | 6.5 | 9.1 | 9.1 | 9.1 |
| Mandelbrot / worker | 89.8 | 89.8 | 89.7 | 89.9 |

All eight worker captures had zero observed ticker intervals longer than 1.5 display periods. Native code improved compute latency, but keeping work off the UI isolate made the largest difference to animation responsiveness in these examples. Heavy native work still stalled the UI when called synchronously there.

## Evidence and checks

- [Repeated device suite: raw JSON](../../docs/results/20261117-212842-results.json).
- [Initial device suite: raw JSON](../../docs/results/20261117-212503-results.json) retained for comparison. Its blur samples had substantially higher variance immediately after installation; the cause was not established. The repeat avoided reinstalling and produced tighter timings. Both suites completed successfully, with 8 compute comparisons and 18 animation captures each.
- The initial correctness run passed 8 tests, including native/Dart byte comparisons at 16 x 16 and 31 x 31, independent filter behavior, known fractal points, and statistics. The expanded suite has 15 tests; see the [test sources](../../test/).
- Scoped Dart analysis passed without issues. The Android release APK built successfully.

Raw JSON contains every compute sample, median/p95, output checksum, job count/latency, refresh rate, ticker gaps, frame build/raster statistics, build mode, and device/battery metadata. Timing boundaries and limitations are described in [README.md](README.md). Curated reports are published in `docs/results/`; new runtime artifacts remain local and ignored by Git.

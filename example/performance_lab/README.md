# Flutter performance lab: Dart, Rust, C++, C

A second entry point for the existing app. The original `lib/main.dart` benchmark remains available.

See [RESULTS.md](RESULTS.md) for measured results and raw reports from the connected Android phone.

## Run on the connected Android phone

From the repository root:

```powershell
flutter devices
flutter run --release -d <device-id> -t example/performance_lab/main.dart
```

The UI has two views:

1. **Speed** answers “Which language finishes sooner?” Choose **Image blur** or **Fractal**, select the dimensions, and tap **Compare speed**. A live status shows verification, warm-up and actual timed runs. Only the chosen task runs. Results report median milliseconds, mark the quickest engine, explain its speed relative to Dart, and display the correct output preview. Blur shows its input and filtered output side by side.
2. **Smoothness** answers “Does the animation pause?” Choose a language and tap **Compare UI vs background**. This runs an idle baseline, work on the UI thread, then work in a persistent background isolate. Watch the single moving dot, which represents the Flutter animation. Paired results show animation updates/sec and long gaps. The live marker stays visible while scrolling. The comparison takes about 12 seconds.
3. **More test options** lets you run a single execution mode or all eight language/mode combinations, plus the baseline. **Run history & detailed timings** retains the completed measurements. Stop finishes the current measurement before ending a comparison.
4. The **export** icon copies the full JSON report. The **help** icon explains the tests and timing boundaries. Results are automatically brought into view after a comparison. Results from another task, size or language are excluded from the current comparison.

Use release mode for speed comparisons. Debug-mode Dart is not a fair comparison to optimized native code. Profile mode is useful for investigating frames with DevTools.

## Automated real-device suite

This builds and installs a release ARM64 APK, runs both workloads and all execution modes, and saves JSON, logcat, device information and a screenshot under `artifacts/`:

```powershell
./example/performance_lab/run-device.ps1 -Device <device-id>
```

The script supports `-Adb <path>` and `-Flutter <path>`. Keep the phone unlocked and the app in the foreground. It records battery temperature before and after. `-Interactive` builds the normal manual app. `-SkipBuild` uses the last APK; it must have been built for the corresponding interactive/automatic mode. Use `-SkipBuild -SkipInstall` to repeat an already installed automatic suite without reinstalling.

Automation uses `--dart-define=LAB_AUTO=true`. Rebuild without that define for ordinary interactive use.

## Workloads and what they tell you

| Workload | Work performed | Potential application |
| --- | --- | --- |
| Image blur | Direct 11 x 11 grayscale box filter, zero border | CPU image processing, loop and memory costs |
| Mandelbrot | Double-precision fractal, up to 400 iterations per pixel | Procedural images, numerical computation |

Both produce real pixel buffers. The blur preview is grayscale, while the fractal preview uses a Dart-applied color palette. The dot in Smoothness is an ordinary Flutter animation running alongside the selected CPU workload.

The box filter deliberately uses the same straightforward algorithm in all languages. A separable/sliding-window filter or a GPU implementation can improve the algorithm far more than changing languages. This lab does not compare those alternatives. C and C++ compile the same shared source, so similar timings are expected. Rust uses safe slice indexing; Dart uses typed arrays. Compiler vectorization and bounds-check elimination can affect results.

## Timing boundaries

- **Compute:** preallocated buffers, one kernel call per sample, FFI overhead included. Allocation, input generation, validation, worker startup, messaging, output copies and preview conversion are outside the stopwatch. All languages run serially on one background isolate. No native kernel creates threads.
- **Animation:** each case warms up before measurement. UI mode calls the kernel synchronously on the UI isolate. Worker mode sends small messages to a persistent isolate whose buffers stay in that isolate. Its job latency includes message round trips, and jobs never overlap. Jobs are scheduled after a Flutter frame, at most one outstanding job at a time. This is a responsiveness experiment, not a saturated throughput comparison.
- **Animation FPS:** Flutter animation-ticker intervals divided by the capture duration. A late interval exceeds 1.5 display periods. This estimates UI scheduling stalls; it is not a count of presented/dropped GPU frames. The JSON also includes p95 UI build and raster durations from `FrameTiming`. Timing callbacks arrive in batches, so boundary frames may be included.
- The first tick has no preceding interval, so even the idle baseline's FPS can be slightly below its actual cadence. Adaptive refresh rates, system load, heat, CPU scheduling, and test order affect results. Compare against the included idle baseline and repeat runs.
- Native kernels use regular, non-leaf FFI calls so long computations can cooperate with Dart VM synchronization. Calling C/Rust/C++ synchronously on the UI isolate still blocks that isolate.

## Build and source layout

The root `hook/build.dart` builds C and C++ with `native_toolchain_c` at `-O3` (MSVC uses `/O2`) and Rust with Cargo's release profile (`opt-level=3`, LTO). C/C++ disable fused multiply-add to match the scalar Dart and Rust expressions; no fast-math is enabled. Android C++ links its runtime statically. The root Rust crate imports the lab module and exports a C ABI. Platform shells need no extra Gradle/CMake integration.

| File | Purpose |
| --- | --- |
| `main.dart` | Guided tests, frame measurements, report export |
| `lab_ui.dart` | Settings, measured-result cards, previews, live animation marker |
| `benchmark.dart` | Randomized measurements, exact-output validation, persistent worker |
| `kernels.dart` | Dart kernels, FFI declarations, buffer ownership |
| `native/kernels.h` | Shared C/C++ implementation |
| `native/c_kernels.c`, `native/cpp_kernels.cpp` | Separate C/C++ exports |
| `native/kernels.rs` | Matching Rust implementation |

Prerequisites: Flutter/Dart compatible with the root `pubspec.yaml`, the Android SDK/NDK, Cargo/Rust, and `rustup target add aarch64-linux-android` for an ARM64 phone. Existing build hooks support Android, Windows and Linux; this work validates Android only. Web and iOS integration are not supplied.

```powershell
flutter test test/performance_lab_test.dart test/performance_lab_ui_test.dart
dart analyze example/performance_lab hook/build.dart test/performance_lab_test.dart test/performance_lab_ui_test.dart
```

The tests check native/Dart equality, known image-filter behavior, known fractal points, timing statistics, selected-task previews and progress, small-screen/large-text layouts, and result filtering. The device suite additionally requires exact pixel equality for all four engines at the selected dimensions. A failed comparison stops the suite instead of reporting a speedup.

## UI review

The redesigned interface was reviewed on the connected CPH2467 in release mode. Both image blur and fractal selection were exercised, including native-output verification and their corresponding previews. The guided idle/UI/background animation comparison was checked on the phone. The current UI and kernel test run passed all 15 tests, including 320 x 568 and 390 x 844 layouts at 1.4x text scaling, preventing values from older comparisons appearing in a new run, and scrolling/expanding sections across repeated tab switches. Scoped analysis passed without issues.

Every collapsible section has a unique `PageStorageKey`. This separates its boolean expansion state from the containing list's stored scroll offset, fixing a gray error panel caused by a `double`/`bool` cast. The navigation regression reproduced that failure before the fix and passes afterward. Framework errors are emitted to the device log as structured error records and fail automated device validation.

The fixed release was also exercised on the phone: all three sections were expanded, both tabs were restored, and the app log contained no Flutter exceptions.

Published evidence: [Speed screenshot](../../docs/screenshots/speed.png), [Smoothness screenshot](../../docs/screenshots/smoothness.png), [repeated device suite](../../docs/results/20261117-212842-results.json), and [Hinglish walkthrough](../../docs/video/README.md). Local build/debug logs and production scratch files are ignored by Git.

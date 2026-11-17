import 'dart:isolate';

import 'dart_bench.dart';
import 'native_bindings.dart';

enum Lang { dart, cpp, rust }

class BenchDef {
  const BenchDef(this.name, this.description, this.arg, this.impls);
  final String name;
  final String description;
  final int arg;
  final Map<Lang, int Function(int)> impls;
}

/// One measured result: median time over [runs] runs, plus the value returned
/// (used to check all three languages computed the same answer).
class BenchResult {
  BenchResult(this.medianMicros, this.value);
  final int medianMicros;
  final int value;
}

const callCount = 10000000;

// Top-level functions so they can be sent to a background isolate.
int _callsDart(int n) {
  var acc = 0;
  for (var i = 0; i < n; i++) {
    acc = dartAdd(acc, i);
  }
  return acc;
}

int _callsCpp(int n) {
  var acc = 0;
  for (var i = 0; i < n; i++) {
    acc = cppAdd(acc, i);
  }
  return acc;
}

int _callsRust(int n) {
  var acc = 0;
  for (var i = 0; i < n; i++) {
    acc = rustAdd(acc, i);
  }
  return acc;
}

final benchmarks = <BenchDef>[
  const BenchDef('Fibonacci (recursive)', 'fib(35), ~30M function calls', 35, {
    Lang.dart: dartFib,
    Lang.cpp: cppFib,
    Lang.rust: rustFib,
  }),
  const BenchDef('Prime sieve', 'count primes below 20,000,000', 20000000, {
    Lang.dart: dartSieve,
    Lang.cpp: cppSieve,
    Lang.rust: rustSieve,
  }),
  const BenchDef('Mandelbrot', '1000×1000 pixels, 500 max iterations', 1000, {
    Lang.dart: dartMandelbrot,
    Lang.cpp: cppMandelbrot,
    Lang.rust: rustMandelbrot,
  }),
  const BenchDef('Sort', 'generate + sort 2,000,000 ints', 2000000, {
    Lang.dart: dartSort,
    Lang.cpp: cppSort,
    Lang.rust: rustSort,
  }),
  const BenchDef(
      'Call overhead', '10M calls to add(a, b) from a Dart loop', callCount, {
    Lang.dart: _callsDart,
    Lang.cpp: _callsCpp,
    Lang.rust: _callsRust,
  }),
];

const runsPerBench = 5;

/// Runs one benchmark for one language on a background isolate so the UI stays
/// responsive: 1 warm-up run, then [runsPerBench] timed runs; returns the median.
Future<BenchResult> runBench(BenchDef def, Lang lang) {
  final fn = def.impls[lang]!;
  final arg = def.arg;
  return Isolate.run(() {
    var value = fn(arg); // warm-up
    final times = <int>[];
    for (var r = 0; r < runsPerBench; r++) {
      final sw = Stopwatch()..start();
      value = fn(arg);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    return BenchResult(times[times.length ~/ 2], value);
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../example/performance_lab/benchmark.dart';
import '../example/performance_lab/kernels.dart';

void main() {
  test(
    'selected task returns four matching results and the correct preview',
    () async {
      final updates = <BenchmarkProgress>[];
      final result = await runSuite(
        16,
        only: Workload.blur,
        onProgress: updates.add,
      );
      expect(result.measurements.length, 4);
      expect(
        result.measurements.every((m) => m.workload == Workload.blur),
        isTrue,
      );
      expect(result.measurements.map((m) => m.hash).toSet().length, 1);
      expect(result.previews.keys, [Workload.blur]);
      expect(result.previews[Workload.blur]!.length, 16 * 16);
      expect(updates.any((u) => u.timing), isTrue);
      expect(updates.every((u) => u.fraction >= 0 && u.fraction <= 1), isTrue);
    },
  );

  for (final side in [16, 31]) {
    for (final workload in Workload.values) {
      test('all native engines match Dart: ${workload.label}, $side px', () {
        final reference = KernelSession(Engine.dart, workload, side);
        try {
          reference.run();
          for (final engine in [Engine.rust, Engine.cpp, Engine.c]) {
            final native = KernelSession(engine, workload, side);
            try {
              native.run();
              expect(
                native.output,
                orderedEquals(reference.output),
                reason: engine.label,
              );
            } finally {
              native.dispose();
            }
          }
        } finally {
          reference.dispose();
        }
      });
    }
  }

  test('box filter preserves constant interior and leaves borders zero', () {
    final input = Uint8List(16 * 16)..fillRange(0, 16 * 16, 99);
    final output = Uint8List(16 * 16);
    dartBlur(input, output, 16, 1);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        expect(
          output[y * 16 + x],
          x == 0 || x == 15 || y == 0 || y == 15 ? 0 : 99,
        );
      }
    }
  });

  test(
    'box filter distributes a single impulse over the correct neighbors',
    () {
      final input = Uint8List(16 * 16)..[8 * 16 + 8] = 225;
      final output = Uint8List(16 * 16);
      dartBlur(input, output, 16, 1);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          expect(
            output[y * 16 + x],
            (x - 8).abs() <= 1 && (y - 8).abs() <= 1 ? 25 : 0,
          );
        }
      }
    },
  );

  test('fractal encodes known escaped and interior points', () {
    final output = Uint8List(16 * 16);
    dartFractal(output, 16, 400);
    expect(output[0], 1); // c = -2 - 1.25i escapes after one iteration.
    expect(output[8 * 16 + 8], 400 % 256); // c = -0.75 stays bounded.
  });

  test('nearest-rank median resists an outlier and p95 includes it', () {
    expect(percentile([4, 2, 3, 1, 999], 0.5), 3);
    expect(percentile([4, 2, 3, 1, 999], 0.95), 999);
    expect(percentile([], 0.5), 0);
  });
}

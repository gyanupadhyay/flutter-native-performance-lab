// Pure Dart versions. Same algorithms as rust/src/lib.rs and src/cpp_bench.cpp.
import 'dart:typed_data';

int dartFib(int n) => n < 2 ? n : dartFib(n - 1) + dartFib(n - 2);

int dartSieve(int n) {
  final composite = Uint8List(n);
  var count = 0;
  for (var i = 2; i < n; i++) {
    if (composite[i] == 0) {
      count++;
      for (var j = i * i; j < n; j += i) {
        composite[j] = 1;
      }
    }
  }
  return count;
}

int dartMandelbrot(int size) {
  const maxIter = 500;
  var total = 0;
  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      final x0 = -2.0 + 2.5 * px.toDouble() / size.toDouble();
      final y0 = -1.25 + 2.5 * py.toDouble() / size.toDouble();
      var x = 0.0, y = 0.0;
      var i = 0;
      while (x * x + y * y <= 4.0 && i < maxIter) {
        final xt = x * x - y * y + x0;
        y = 2.0 * x * y + y0;
        x = xt;
        i++;
      }
      total += i;
    }
  }
  return total;
}

int dartSort(int n) {
  final v = Int32List(n);
  var x = 2463534242;
  for (var i = 0; i < n; i++) {
    x = (x ^ (x << 13)) & 0xFFFFFFFF;
    x ^= x >> 17;
    x = (x ^ (x << 5)) & 0xFFFFFFFF;
    v[i] = x; // Int32List wraps the uint32 into int32, same as the casts in C++/Rust.
  }
  v.sort();
  var sum = 0;
  for (var i = 0; i < n; i++) {
    sum += v[i] * (i & 7);
  }
  return sum;
}

/// Kept out-of-line so the "call overhead" test compares a real Dart call
/// against a real FFI call.
@pragma('vm:never-inline')
int dartAdd(int a, int b) => a + b;

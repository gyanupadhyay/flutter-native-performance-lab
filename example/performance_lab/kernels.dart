import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

enum Engine { dart, rust, cpp, c }

extension EngineLabel on Engine {
  String get label => switch (this) {
    Engine.dart => 'Dart',
    Engine.rust => 'Rust',
    Engine.cpp => 'C++',
    Engine.c => 'C',
  };
}

enum Workload { blur, fractal }

extension WorkloadLabel on Workload {
  String get label => switch (this) {
    Workload.blur => 'Image blur',
    Workload.fractal => 'Mandelbrot',
  };
  String get description => switch (this) {
    Workload.blur =>
      '11 x 11 grayscale box filter. Integer loops and memory access.',
    Workload.fractal => '400 iterations per pixel. Floating-point computation.',
  };
  int get parameter => this == Workload.blur ? 5 : 400;
}

typedef _Kernel = Void Function(Pointer<Uint8>, Pointer<Uint8>, Int64, Int64);

// Deliberately non-leaf: these CPU kernels can run for many milliseconds.
@Native<_Kernel>(assetId: 'package:native_bench/lab_c', symbol: 'lab_c_blur')
external void _cBlur(
  Pointer<Uint8> src,
  Pointer<Uint8> out,
  int side,
  int radius,
);
@Native<_Kernel>(assetId: 'package:native_bench/lab_c', symbol: 'lab_c_fractal')
external void _cFractal(
  Pointer<Uint8> src,
  Pointer<Uint8> out,
  int side,
  int iterations,
);
@Native<_Kernel>(
  assetId: 'package:native_bench/lab_cpp',
  symbol: 'lab_cpp_blur',
)
external void _cppBlur(
  Pointer<Uint8> src,
  Pointer<Uint8> out,
  int side,
  int radius,
);
@Native<_Kernel>(
  assetId: 'package:native_bench/lab_cpp',
  symbol: 'lab_cpp_fractal',
)
external void _cppFractal(
  Pointer<Uint8> src,
  Pointer<Uint8> out,
  int side,
  int iterations,
);
@Native<_Kernel>(
  assetId: 'package:native_bench/rust_bench',
  symbol: 'lab_rust_blur',
)
external void _rustBlur(
  Pointer<Uint8> src,
  Pointer<Uint8> out,
  int side,
  int radius,
);
@Native<_Kernel>(
  assetId: 'package:native_bench/rust_bench',
  symbol: 'lab_rust_fractal',
)
external void _rustFractal(
  Pointer<Uint8> src,
  Pointer<Uint8> out,
  int side,
  int iterations,
);

void dartBlur(Uint8List src, Uint8List out, int side, int radius) {
  final diameter = radius * 2 + 1;
  for (var y = radius; y < side - radius; y++) {
    for (var x = radius; x < side - radius; x++) {
      var sum = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          sum += src[(y + dy) * side + x + dx];
        }
      }
      out[y * side + x] = sum ~/ (diameter * diameter);
    }
  }
}

void dartFractal(Uint8List out, int side, int maxIter) {
  for (var py = 0; py < side; py++) {
    for (var px = 0; px < side; px++) {
      final x0 = -2.0 + 2.5 * px.toDouble() / side.toDouble();
      final y0 = -1.25 + 2.5 * py.toDouble() / side.toDouble();
      var x = 0.0;
      var y = 0.0;
      var i = 0;
      while (x * x + y * y <= 4.0 && i < maxIter) {
        final xt = x * x - y * y + x0;
        y = 2.0 * x * y + y0;
        x = xt;
        i++;
      }
      out[py * side + px] = i % 256;
    }
  }
}

/// All engines use equally sized preallocated byte buffers, outside timing.
/// Native calls include FFI overhead; output copying/checking is measured separately.
class KernelSession {
  KernelSession(this.engine, this.workload, this.side) {
    if (side < 16 || side > 1024) throw ArgumentError.value(side, 'side');
    if (engine == Engine.dart) {
      input = Uint8List(side * side);
      output = Uint8List(side * side);
    } else {
      _src = calloc<Uint8>(side * side);
      _out = calloc<Uint8>(side * side);
      input = _src.asTypedList(side * side);
      output = _out.asTypedList(side * side);
    }
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        input[y * side + x] = ((x * 13 + y * 7) ^ ((x * y) >> 3)) & 255;
      }
    }
  }

  final Engine engine;
  final Workload workload;
  final int side;
  late final Uint8List input;
  late final Uint8List output;
  Pointer<Uint8> _src = nullptr;
  Pointer<Uint8> _out = nullptr;

  void run() {
    final parameter = workload.parameter;
    switch (engine) {
      case Engine.dart:
        if (workload == Workload.blur) {
          dartBlur(input, output, side, parameter);
        } else {
          dartFractal(output, side, parameter);
        }
      case Engine.c:
        (workload == Workload.blur ? _cBlur : _cFractal)(
          _src,
          _out,
          side,
          parameter,
        );
      case Engine.cpp:
        (workload == Workload.blur ? _cppBlur : _cppFractal)(
          _src,
          _out,
          side,
          parameter,
        );
      case Engine.rust:
        (workload == Workload.blur ? _rustBlur : _rustFractal)(
          _src,
          _out,
          side,
          parameter,
        );
    }
  }

  void dispose() {
    if (_src != nullptr) calloc.free(_src);
    if (_out != nullptr) calloc.free(_out);
    _src = nullptr;
    _out = nullptr;
  }
}

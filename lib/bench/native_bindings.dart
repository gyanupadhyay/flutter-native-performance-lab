// Direct Dart -> native calls. No MethodChannel and no codegen: @Native looks up
// the C-ABI symbol in the library the build hook bundled under `assetId`.
// isLeaf: true = the function never calls back into Dart, which makes calls cheaper.
import 'dart:ffi';

const _rust = 'package:native_bench/rust_bench';
const _cpp = 'package:native_bench/cpp_bench';

// ---- Rust ----
@Native<Int64 Function(Int64)>(assetId: _rust, symbol: 'rust_fib', isLeaf: true)
external int rustFib(int n);

@Native<Int64 Function(Int64)>(assetId: _rust, symbol: 'rust_sieve', isLeaf: true)
external int rustSieve(int n);

@Native<Int64 Function(Int64)>(
    assetId: _rust, symbol: 'rust_mandelbrot', isLeaf: true)
external int rustMandelbrot(int size);

@Native<Int64 Function(Int64)>(assetId: _rust, symbol: 'rust_sort', isLeaf: true)
external int rustSort(int n);

@Native<Int64 Function(Int64, Int64)>(
    assetId: _rust, symbol: 'rust_add', isLeaf: true)
external int rustAdd(int a, int b);

// ---- C++ ----
@Native<Int64 Function(Int64)>(assetId: _cpp, symbol: 'cpp_fib', isLeaf: true)
external int cppFib(int n);

@Native<Int64 Function(Int64)>(assetId: _cpp, symbol: 'cpp_sieve', isLeaf: true)
external int cppSieve(int n);

@Native<Int64 Function(Int64)>(
    assetId: _cpp, symbol: 'cpp_mandelbrot', isLeaf: true)
external int cppMandelbrot(int size);

@Native<Int64 Function(Int64)>(assetId: _cpp, symbol: 'cpp_sort', isLeaf: true)
external int cppSort(int n);

@Native<Int64 Function(Int64, Int64)>(
    assetId: _cpp, symbol: 'cpp_add', isLeaf: true)
external int cppAdd(int a, int b);

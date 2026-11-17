//! Rust side of the benchmark. Every exported function uses the C ABI
//! (`extern "C"` + `#[unsafe(no_mangle)]`) so Dart can call it with `@Native`.
//! The algorithms match lib/bench/dart_bench.dart and src/cpp_bench.cpp step for step.

#[path = "../../example/performance_lab/native/kernels.rs"]
mod performance_lab;

/// 1. Recursive Fibonacci: function-call overhead.
#[unsafe(no_mangle)]
pub extern "C" fn rust_fib(n: i64) -> i64 {
    fn fib(n: i64) -> i64 {
        if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
    }
    fib(n)
}

/// 2. Sieve of Eratosthenes: count primes below `n` (memory and loops).
#[unsafe(no_mangle)]
pub extern "C" fn rust_sieve(n: i64) -> i64 {
    let n = n as usize;
    let mut composite = vec![0u8; n];
    let mut count = 0i64;
    let mut i = 2;
    while i < n {
        if composite[i] == 0 {
            count += 1;
            let mut j = i * i;
            while j < n {
                composite[j] = 1;
                j += i;
            }
        }
        i += 1;
    }
    count
}

/// 3. Mandelbrot set on a size x size grid, max 500 iterations (floating point).
#[unsafe(no_mangle)]
pub extern "C" fn rust_mandelbrot(size: i64) -> i64 {
    let max_iter = 500;
    let mut total = 0i64;
    for py in 0..size {
        for px in 0..size {
            let x0 = -2.0 + 2.5 * (px as f64) / (size as f64);
            let y0 = -1.25 + 2.5 * (py as f64) / (size as f64);
            let (mut x, mut y) = (0.0f64, 0.0f64);
            let mut i = 0;
            while x * x + y * y <= 4.0 && i < max_iter {
                let xt = x * x - y * y + x0;
                y = 2.0 * x * y + y0;
                x = xt;
                i += 1;
            }
            total += i as i64;
        }
    }
    total
}

/// 4. Generate `n` pseudo-random ints (xorshift32), sort them, return a checksum.
#[unsafe(no_mangle)]
pub extern "C" fn rust_sort(n: i64) -> i64 {
    let n = n as usize;
    let mut v = Vec::with_capacity(n);
    let mut x: u32 = 2463534242;
    for _ in 0..n {
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        v.push(x as i32);
    }
    v.sort_unstable();
    let mut sum = 0i64;
    for (i, &e) in v.iter().enumerate() {
        sum += e as i64 * ((i & 7) as i64);
    }
    sum
}

/// 5. Tiny function used to measure the cost of a single Dart -> Rust call.
#[unsafe(no_mangle)]
pub extern "C" fn rust_add(a: i64, b: i64) -> i64 {
    a.wrapping_add(b)
}

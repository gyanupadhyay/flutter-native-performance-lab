//! Matching scalar kernels. Buffer ownership stays with Dart.
//! Caller supplies valid, non-overlapping side*side byte buffers.

#[unsafe(no_mangle)]
pub unsafe extern "C" fn lab_rust_blur(src: *const u8, out: *mut u8, side: i64, radius: i64) {
    let side = side as usize;
    let radius = radius as usize;
    let input = unsafe { std::slice::from_raw_parts(src, side * side) };
    let output = unsafe { std::slice::from_raw_parts_mut(out, side * side) };
    let diameter = radius * 2 + 1;
    for y in radius..side - radius {
        for x in radius..side - radius {
            let mut sum = 0u32;
            for yy in y - radius..=y + radius {
                for xx in x - radius..=x + radius {
                    sum += input[yy * side + xx] as u32;
                }
            }
            output[y * side + x] = (sum as usize / (diameter * diameter)) as u8;
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn lab_rust_fractal(_src: *const u8, out: *mut u8, side: i64, max_iter: i64) {
    let output = unsafe { std::slice::from_raw_parts_mut(out, (side * side) as usize) };
    for py in 0..side {
        for px in 0..side {
            let x0 = -2.0 + 2.5 * px as f64 / side as f64;
            let y0 = -1.25 + 2.5 * py as f64 / side as f64;
            let (mut x, mut y) = (0.0f64, 0.0f64);
            let mut i = 0;
            while x * x + y * y <= 4.0 && i < max_iter {
                let xt = x * x - y * y + x0;
                y = 2.0 * x * y + y0;
                x = xt;
                i += 1;
            }
            output[(py * side + px) as usize] = (i % 256) as u8;
        }
    }
}

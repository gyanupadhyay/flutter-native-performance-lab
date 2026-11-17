// Build hook: Flutter runs this automatically on `flutter run` / `flutter build`.
// It compiles the original C++ benchmark, the performance lab's C/C++ kernels,
// and the Rust crate for the target device, then bundles the libraries
// into the app. No Gradle/CMake/Xcode changes are needed.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final logger = Logger('')
      ..level = Level.ALL
      ..onRecord.listen((r) => stderr.writeln(r.message));
    final os = input.config.code.targetOS;

    // C++ -> package:native_bench/cpp_bench
    await CBuilder.library(
      name: 'cpp_bench',
      assetName: 'cpp_bench',
      sources: ['src/cpp_bench.cpp'],
      language: Language.cpp,
      // Bundle libc++ inside the .so instead of shipping libc++_shared.so.
      cppLinkStdLib: os == OS.android ? 'c++_static' : null,
      // Stop clang fusing a*b+c into FMA, so float results match Dart and Rust exactly.
      flags: os == OS.windows ? const ['/EHsc'] : const ['-ffp-contract=off'],
    ).run(input: input, output: output, logger: logger);

    for (final language in [Language.c, Language.cpp]) {
      final isCpp = language == Language.cpp;
      final name = isCpp ? 'lab_cpp' : 'lab_c';
      await CBuilder.library(
        name: name,
        assetName: name,
        sources: [
          'example/performance_lab/native/${isCpp ? 'cpp_kernels.cpp' : 'c_kernels.c'}',
        ],
        language: language,
        cppLinkStdLib: isCpp && os == OS.android ? 'c++_static' : null,
        optimizationLevel: OptimizationLevel.o3,
        flags: os == OS.windows
            ? const ['/fp:strict']
            : const ['-ffp-contract=off'],
      ).run(input: input, output: output, logger: logger);
    }
    output.dependencies.add(
      input.packageRoot.resolve('example/performance_lab/native/kernels.h'),
    );

    // Rust -> package:native_bench/rust_bench
    await _buildRust(input, output);
  });
}

Future<void> _buildRust(BuildInput input, BuildOutputBuilder output) async {
  final code = input.config.code;
  final os = code.targetOS;
  final arch = code.targetArchitecture;
  final env = <String, String>{};

  final String triple;
  final String libFile;
  if (os == OS.android) {
    final (t, clangPrefix) = switch (arch) {
      Architecture.arm64 => ('aarch64-linux-android', 'aarch64-linux-android'),
      Architecture.arm => (
        'armv7-linux-androideabi',
        'armv7a-linux-androideabi',
      ),
      Architecture.x64 => ('x86_64-linux-android', 'x86_64-linux-android'),
      Architecture.ia32 => ('i686-linux-android', 'i686-linux-android'),
      _ => throw UnsupportedError('Unsupported Android arch: $arch'),
    };
    triple = t;
    // Flutter hands us the NDK's clang; Rust uses it as the linker.
    final api = code.android.targetNdkApi;
    final binDir = File.fromUri(code.cCompiler!.compiler).parent.path;
    final ext = Platform.isWindows ? '.cmd' : '';
    final linker = '$binDir${Platform.pathSeparator}$clangPrefix$api-clang$ext';
    env['CARGO_TARGET_${triple.toUpperCase().replaceAll('-', '_')}_LINKER'] =
        linker;
    libFile = 'librust_bench.so';
  } else if (os == OS.windows) {
    triple = arch == Architecture.arm64
        ? 'aarch64-pc-windows-msvc'
        : 'x86_64-pc-windows-msvc';
    libFile = 'rust_bench.dll';
  } else if (os == OS.linux) {
    triple = arch == Architecture.arm64
        ? 'aarch64-unknown-linux-gnu'
        : 'x86_64-unknown-linux-gnu';
    libFile = 'librust_bench.so';
  } else {
    throw UnsupportedError(
      'This demo builds Rust for Android/Windows/Linux only.',
    );
  }

  // Hooks run with a reduced environment, so locate cargo explicitly.
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  var cargo = 'cargo';
  if (home != null) {
    final exe = Platform.isWindows ? 'cargo.exe' : 'cargo';
    final candidate = File('$home/.cargo/bin/$exe');
    if (candidate.existsSync()) {
      cargo = candidate.path;
      env['CARGO_HOME'] ??=
          Platform.environment['CARGO_HOME'] ?? '$home/.cargo';
      env['RUSTUP_HOME'] ??=
          Platform.environment['RUSTUP_HOME'] ?? '$home/.rustup';
    }
  }

  final crateDir = input.packageRoot.resolve('rust/');
  final targetDir = input.outputDirectoryShared.resolve('cargo_target/');
  env['CARGO_TARGET_DIR'] = targetDir.toFilePath();

  final result = await Process.run(cargo, [
    'build',
    '--release',
    '--target',
    triple,
    '--manifest-path',
    crateDir.resolve('Cargo.toml').toFilePath(),
  ], environment: env);
  if (result.exitCode != 0) {
    throw Exception(
      'cargo build failed (is Rust installed and `rustup target add $triple` done?)\n'
      '${result.stdout}\n${result.stderr}',
    );
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'rust_bench',
      linkMode: DynamicLoadingBundled(),
      file: targetDir.resolve('$triple/release/$libFile'),
    ),
  );
  // Rebuild when Rust sources change.
  output.dependencies.add(crateDir.resolve('Cargo.toml'));
  output.dependencies.add(
    input.packageRoot.resolve('example/performance_lab/native/kernels.rs'),
  );
  for (final f in Directory.fromUri(crateDir.resolve('src/')).listSync()) {
    output.dependencies.add(f.uri);
  }
}

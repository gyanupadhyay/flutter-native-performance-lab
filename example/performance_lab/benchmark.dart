import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'kernels.dart';

const measuredRuns = 7;
const warmupRuns = 2;

double percentile(List<num> samples, double fraction) {
  if (samples.isEmpty) return 0;
  final ordered = samples.map((s) => s.toDouble()).toList()..sort();
  return ordered[(fraction * ordered.length).ceil().clamp(1, ordered.length) -
      1];
}

int checksum(Uint8List pixels) {
  var hash = 0;
  for (final pixel in pixels) {
    hash = (hash * 31 + pixel) & 0xFFFFFFFF;
  }
  return hash;
}

class Measurement {
  Measurement(this.engine, this.workload, this.micros, this.hash);
  final Engine engine;
  final Workload workload;
  final List<int> micros;
  final int hash;
  double get medianMs => percentile(micros, 0.5) / 1000;
  Map<String, Object> toJson() => {
    'engine': engine.label,
    'workload': workload.label,
    'median_ms': medianMs,
    'p95_ms': percentile(micros, 0.95) / 1000,
    'samples_us': micros,
    'checksum': hash,
    'exact_output_match': true,
  };
}

class SuiteResult {
  SuiteResult(this.measurements, this.previews, this.side);
  final List<Measurement> measurements;
  final Map<Workload, Uint8List> previews;
  final int side;
}

class BenchmarkProgress {
  const BenchmarkProgress(
    this.message,
    this.completed,
    this.total, {
    this.timing = false,
  });
  final String message;
  final int completed;
  final int total;
  final bool timing;
  double get fraction => completed / total;
}

Future<SuiteResult> runSuite(
  int side, {
  Workload? only,
  void Function(BenchmarkProgress)? onProgress,
}) async {
  final updates = ReceivePort();
  final listener = updates.listen((message) {
    if (message is BenchmarkProgress) onProgress?.call(message);
  });
  try {
    return await _spawnSuite((side, only, updates.sendPort));
  } finally {
    await listener.cancel();
    updates.close();
  }
}

// Keep the isolate closure away from UI callbacks and their captured State.
Future<SuiteResult> _spawnSuite((int, Workload?, SendPort) config) =>
    Isolate.run(
      () => measureSuite(config.$1, only: config.$2, updates: config.$3),
    );

SuiteResult measureSuite(int side, {Workload? only, SendPort? updates}) {
  final results = <Measurement>[];
  final random = Random(20261117);
  final previews = <Workload, Uint8List>{};
  final workloads = only == null ? Workload.values : [only];
  final total =
      workloads.length * Engine.values.length * (measuredRuns + warmupRuns + 1);
  var completed = 0;
  void progress(String message, {bool timing = false}) => updates?.send(
    BenchmarkProgress(message, completed, total, timing: timing),
  );
  for (final workload in workloads) {
    final sessions = {
      for (final engine in Engine.values)
        engine: KernelSession(engine, workload, side),
    };
    try {
      final reference = sessions[Engine.dart]!;
      progress('Preparing ${workload.label.toLowerCase()} input');
      reference.run();
      for (final session in sessions.values) {
        progress('Warming up ${session.engine.label}');
        for (var i = 0; i < warmupRuns; i++) {
          session.run();
          completed++;
        }
        // Compare every output byte; a checksum alone can hide mismatches.
        for (var i = 0; i < reference.output.length; i++) {
          if (session.output[i] != reference.output[i]) {
            throw StateError(
              '${session.engine.label} ${workload.label}: mismatch at pixel $i',
            );
          }
        }
        completed++;
        progress('${session.engine.label}: matching output verified');
      }
      final samples = {for (final engine in Engine.values) engine: <int>[]};
      for (var round = 0; round < measuredRuns; round++) {
        final order = Engine.values.toList()..shuffle(random);
        for (final engine in order) {
          progress(
            '${engine.label}: timed run ${round + 1} of $measuredRuns',
            timing: true,
          );
          final timer = Stopwatch()..start();
          sessions[engine]!.run();
          timer.stop();
          samples[engine]!.add(timer.elapsedMicroseconds);
          completed++;
        }
      }
      for (final engine in Engine.values) {
        results.add(
          Measurement(
            engine,
            workload,
            samples[engine]!,
            checksum(sessions[engine]!.output),
          ),
        );
      }
      previews[workload] = Uint8List.fromList(reference.output);
    } finally {
      for (final session in sessions.values) {
        session.dispose();
      }
    }
  }
  progress('Comparison complete');
  return SuiteResult(results, previews, side);
}

/// A persistent isolate: allocation, warm-up and startup happen before capture.
/// Each job sends a small message; image buffers remain in the worker.
class KernelWorker {
  KernelWorker._(this._isolate, this._responses, this._commands);
  final Isolate _isolate;
  final ReceivePort _responses;
  final SendPort _commands;
  late final StreamIterator<dynamic> _iterator;

  static Future<KernelWorker> start(
    Engine engine,
    Workload workload,
    int side,
  ) async {
    final responses = ReceivePort();
    final iterator = StreamIterator<dynamic>(responses);
    final isolate = await Isolate.spawn(_workerMain, (
      responses.sendPort,
      engine,
      workload,
      side,
    ));
    await iterator.moveNext();
    final first = iterator.current;
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw StateError('$first');
    }
    return KernelWorker._(isolate, responses, first).._iterator = iterator;
  }

  Future<void> run() async {
    _commands.send('run');
    if (!await _iterator.moveNext() || _iterator.current != 'done') {
      throw StateError('Worker stopped: ${_iterator.current}');
    }
  }

  Future<void> dispose() async {
    _commands.send('stop');
    await _iterator.moveNext(); // worker frees native buffers before exit
    await _iterator.cancel();
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _workerMain((SendPort, Engine, Workload, int) config) async {
  final (reply, engine, workload, side) = config;
  KernelSession? session;
  final commands = ReceivePort();
  try {
    session = KernelSession(engine, workload, side);
    session.run();
    reply.send(commands.sendPort);
    await for (final command in commands) {
      if (command == 'stop') break;
      session.run();
      reply.send('done');
    }
  } catch (error) {
    reply.send('Worker failed: $error');
  } finally {
    session?.dispose();
    commands.close();
    reply.send('stopped');
  }
}

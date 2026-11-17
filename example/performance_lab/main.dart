import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'benchmark.dart';
import 'kernels.dart';
import 'lab_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    presentError?.call(details);
    // Device validation must fail on framework errors as well as kernel errors.
    debugPrint(
      'PERF_LAB ${jsonEncode({'type': 'error', 'source': 'flutter', 'message': details.exceptionAsString()})}',
    );
  };
  runApp(const PerformanceLab());
}

class PerformanceLab extends StatelessWidget {
  const PerformanceLab({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Performance lab',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: labBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: labAccent,
        brightness: Brightness.dark,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 14),
        bodySmall: TextStyle(fontSize: 12),
      ),
      useMaterial3: true,
    ),
    home: const LabPage(),
  );
}

class LabPage extends StatefulWidget {
  const LabPage({super.key});
  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  final _progress = ValueNotifier<double?>(null);
  final _speedResultsKey = GlobalKey();
  final _smoothResultsKey = GlobalKey();
  Workload _workload = Workload.blur;
  Engine _engine = Engine.dart;
  int _side = 512;
  int _page = 0;
  int _comparisonId = 0;
  bool _worker = false;
  bool _busy = false;
  bool _error = false;
  bool _measuring = false;
  bool _stopRequested = false;
  String _operation = 'speed';
  String _title = 'Ready to compare';
  String _detail = 'Check identical output, then time each language.';
  SuiteResult? _suite;
  ui.Image? _preview;
  ui.Image? _inputPreview;
  Workload? _previewTask;
  int _previewVersion = 0;
  final _jankResults = <Map<String, Object>>[];
  final _report = <Map<String, Object>>[];
  final _gaps = <double>[];
  final _uiTimes = <double>[];
  final _rasterTimes = <double>[];
  bool _captureGaps = false;
  bool _captureTimings = false;
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(_tick);
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (const bool.fromEnvironment('LAB_AUTO')) _automatedRun();
    });
  }

  void _tick() {
    final current = _animation.lastElapsedDuration;
    if (_captureGaps && current != null && _lastTick != null) {
      _gaps.add((current - _lastTick!).inMicroseconds / 1000);
    }
    _lastTick = _captureGaps ? current : null;
  }

  void _timings(List<FrameTiming> frames) {
    if (!_captureTimings) return;
    for (final frame in frames) {
      _uiTimes.add(frame.buildDuration.inMicroseconds / 1000);
      _rasterTimes.add(frame.rasterDuration.inMicroseconds / 1000);
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _animation.dispose();
    _progress.dispose();
    _preview?.dispose();
    _inputPreview?.dispose();
    super.dispose();
  }

  void _record(Map<String, Object> result) {
    _report.add(result);
    debugPrint('PERF_LAB ${jsonEncode(result)}');
  }

  Future<void> _guard(
    Future<void> Function() action, {
    String operation = 'speed',
  }) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = false;
      _stopRequested = false;
      _operation = operation;
      if (operation == 'animation') _comparisonId++;
    });
    try {
      await action();
    } catch (error, stack) {
      _record({'type': 'error', 'message': '$error'});
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        setState(() {
          _error = true;
          _title = 'The test could not finish';
          _detail = '$error';
        });
      }
    } finally {
      _captureGaps = false;
      _captureTimings = false;
      if (mounted) {
        setState(() {
          _busy = false;
          _measuring = false;
          if (_stopRequested) {
            _title = 'Stopped after the current test';
            _detail = 'Completed measurements are still available below.';
          }
        });
      }
    }
  }

  Future<void> _compute({bool all = false}) async {
    _progress.value = 0;
    setState(() {
      _suite = null;
      _title = 'Checking that outputs match';
      _detail =
          'Preparing ${taskName(_workload).toLowerCase()} for all four languages.';
    });
    final suite = await runSuite(
      _side,
      only: all ? null : _workload,
      onProgress: (progress) {
        if (!mounted) return;
        _progress.value = progress.fraction;
        setState(() {
          _title = progress.timing
              ? 'Timing each language'
              : 'Preparing a fair comparison';
          _detail = progress.message;
        });
      },
    );
    for (final measurement in suite.measurements) {
      _record({'type': 'compute', 'side': suite.side, ...measurement.toJson()});
    }
    if (!mounted) return;
    setState(() {
      _suite = suite;
      _title = 'Speed comparison complete';
      _detail = 'All four languages produced identical pixels.';
    });
    await _renderPreview(suite, _workload);
    if (!all) _reveal(_speedResultsKey);
  }

  Future<void> _renderPreview(SuiteResult suite, Workload task) async {
    final pixels = suite.previews[task];
    if (pixels == null) return;
    final version = ++_previewVersion;
    final rgba = Uint8List(pixels.length * 4);
    final input = task == Workload.blur ? Uint8List(pixels.length * 4) : null;
    for (var i = 0; i < pixels.length; i++) {
      final value = pixels[i];
      rgba[i * 4] = task == Workload.blur ? value : (value * 3) % 256;
      rgba[i * 4 + 1] = value;
      rgba[i * 4 + 2] = task == Workload.blur ? value : 255 - value;
      rgba[i * 4 + 3] = 255;
      if (input != null) {
        final x = i % suite.side;
        final y = i ~/ suite.side;
        final original = ((x * 13 + y * 7) ^ ((x * y) >> 3)) & 255;
        input[i * 4] = original;
        input[i * 4 + 1] = original;
        input[i * 4 + 2] = original;
        input[i * 4 + 3] = 255;
      }
    }
    Future<ui.Image> decode(Uint8List data) {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        data,
        suite.side,
        suite.side,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return completer.future;
    }

    final image = await decode(rgba);
    final original = input == null ? null : await decode(input);
    if (!mounted || version != _previewVersion) {
      image.dispose();
      original?.dispose();
      return;
    }
    setState(() {
      _preview?.dispose();
      _inputPreview?.dispose();
      _preview = image;
      _inputPreview = original;
      _previewTask = task;
    });
  }

  void _changeTask(Workload task) {
    setState(() {
      _workload = task;
      _stopRequested = false;
    });
    if (_suite?.previews.containsKey(task) ?? false) {
      _renderPreview(_suite!, task);
    }
  }

  void _changeSize(int side) {
    _previewVersion++;
    setState(() {
      _side = side;
      _stopRequested = false;
      _suite = null;
      _preview?.dispose();
      _inputPreview?.dispose();
      _preview = null;
      _inputPreview = null;
      _previewTask = null;
    });
  }

  Future<void> _jankCase({bool baseline = false}) async {
    final label = baseline
        ? 'Baseline: no calculation'
        : '${_engine.label} · ${_worker ? 'background' : 'UI thread'}';
    _progress.value = null;
    setState(() {
      _title = 'Preparing $label';
      _detail = 'Warming up before the 3-second measurement.';
    });
    await SchedulerBinding.instance.endOfFrame;
    KernelSession? session;
    KernelWorker? worker;
    Timer? progressTimer;
    try {
      if (!baseline) {
        if (_worker) {
          worker = await KernelWorker.start(_engine, _workload, _side);
        } else {
          session = KernelSession(_engine, _workload, _side)..run();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final refresh = View.of(context).display.refreshRate;
      final hz = refresh > 0 ? refresh : 60.0;
      final budget = 1000 / hz;
      setState(() {
        _title = label;
        _detail = baseline
            ? 'Watch the dot with no heavy work running.'
            : 'Watch the dot. A pause means the animation was delayed.';
        _measuring = true;
      });
      _gaps.clear();
      _uiTimes.clear();
      _rasterTimes.clear();
      _lastTick = null;
      _captureGaps = true;
      _captureTimings = true;
      _progress.value = 0;
      final timer = Stopwatch()..start();
      progressTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) {
          _progress.value = (timer.elapsedMilliseconds / 3000).clamp(0, 1);
        }
      });
      var jobs = 0;
      final jobTimes = <int>[];
      while (mounted && timer.elapsedMilliseconds < 3000) {
        await SchedulerBinding.instance.endOfFrame;
        if (!baseline) {
          final jobTimer = Stopwatch()..start();
          if (worker != null) {
            await worker.run();
          } else {
            session!.run();
          }
          jobTimes.add(jobTimer.elapsedMicroseconds);
          jobs++;
        }
      }
      await SchedulerBinding.instance.endOfFrame;
      timer.stop();
      progressTimer.cancel();
      _captureGaps = false;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _captureTimings = false;
      final lateGaps = _gaps.where((ms) => ms > budget * 1.5).length;
      final fps = _gaps.length * 1000000 / timer.elapsedMicroseconds;
      final result = <String, Object>{
        'type': 'animation',
        'comparison_id': _comparisonId,
        'engine': baseline ? 'Idle' : _engine.label,
        'execution': baseline ? 'baseline' : (_worker ? 'worker' : 'UI'),
        'workload': _workload.label,
        'side': _side,
        'refresh_hz': hz,
        'elapsed_ms': timer.elapsedMicroseconds / 1000,
        'completed_jobs': jobs,
        'job_median_ms': percentile(jobTimes, 0.5) / 1000,
        'animation_fps': fps,
        'frame_intervals': _gaps.length,
        'late_intervals': lateGaps,
        'late_percent': _gaps.isEmpty ? 0.0 : 100 * lateGaps / _gaps.length,
        'gap_p95_ms': percentile(_gaps, 0.95),
        'max_gap_ms': _gaps.isEmpty ? 0.0 : _gaps.reduce(math.max),
        'ui_p95_ms': percentile(_uiTimes, 0.95),
        'raster_p95_ms': percentile(_rasterTimes, 0.95),
      };
      _record(result);
      if (mounted) {
        _progress.value = 1;
        setState(() {
          _jankResults.add(result);
          _measuring = false;
          _title = '$label finished';
          _detail =
              '${fps.toStringAsFixed(1)} animation updates/sec. See the comparison below.';
        });
      }
    } finally {
      progressTimer?.cancel();
      _captureGaps = false;
      _captureTimings = false;
      session?.dispose();
      await worker?.dispose();
    }
  }

  Future<void> _comparePair() async {
    await _jankCase(baseline: true);
    for (final worker in [false, true]) {
      if (!mounted || _stopRequested) return;
      setState(() => _worker = worker);
      await _jankCase();
    }
    _reveal(_smoothResultsKey);
  }

  Future<void> _compareAnimation() async {
    await _jankCase(baseline: true);
    for (final engine in Engine.values) {
      for (final worker
          in (engine.index.isEven ? [false, true] : [true, false])) {
        if (!mounted || _stopRequested) return;
        setState(() {
          _engine = engine;
          _worker = worker;
        });
        await _jankCase();
      }
    }
    _reveal(_smoothResultsKey);
  }

  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  Future<void> _automatedRun() => _guard(() async {
    _record({
      'type': 'environment',
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'platform': defaultTargetPlatform.name,
      'warmups': warmupRuns,
      'measured_runs': measuredRuns,
    });
    await _compute(all: true);
    for (final workload in Workload.values) {
      if (!mounted || _stopRequested) return;
      setState(() {
        _page = 1;
        _workload = workload;
        _operation = 'animation';
        _comparisonId++;
      });
      if (!_animation.isAnimating) _animation.repeat();
      await _compareAnimation();
    }
    if (_stopRequested) return;
    _record({'type': 'complete', 'result_count': _report.length});
    if (mounted) {
      setState(() {
        _title = 'All device tests finished';
        _detail = 'Use the export button to copy the full report.';
      });
    }
  });

  void _showHelp() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Two questions. Two tests.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            const Text('Speed', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text(
              'How long does each language take to calculate the same image? Lower milliseconds is better. All calculations run in the background for this test.',
              style: TextStyle(color: labMuted, height: 1.5),
            ),
            const SizedBox(height: 18),
            const Text(
              'Smoothness',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Text(
              'Does that work interrupt Flutter’s animation? Compare work on the UI thread with work in a background isolate. Higher animation updates/sec is better.',
              style: TextStyle(color: labMuted, height: 1.5),
            ),
            const SizedBox(height: 18),
            const LabNote(
              'The moving dot is a Flutter animation. Each selected language calculates the image; it does not draw the dot.',
            ),
            const SizedBox(height: 12),
            const LabNote(
              'Long gaps exceed 1.5 display periods. Animation fps measures Flutter ticker updates, not presented GPU frames.',
            ),
            const SizedBox(height: 12),
            const LabNote(
              'Speed timings include the native function call. Buffer allocation, pixel verification, worker startup and image transfer are outside timing. Seven samples are summarized by their median.',
            ),
            const SizedBox(height: 12),
            LabNote(
              'Build: ${kReleaseMode
                  ? 'release (AOT)'
                  : kProfileMode
                  ? 'profile (AOT)'
                  : 'debug — use release for speed comparisons'}. Results depend on this device, its temperature and current load.',
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _export() async {
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_report)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full JSON report copied to clipboard.')),
      );
    }
  }

  Widget _settings() => TaskSettings(
    workload: _workload,
    side: _side,
    onTask: _busy ? null : _changeTask,
    onSide: _busy ? null : _changeSize,
  );

  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: labMuted, fontSize: 13, height: 1.45),
        ),
      ],
    ),
  );

  Widget _speedPage() {
    final selected =
        _suite?.measurements.where((m) => m.workload == _workload).toList() ??
        <Measurement>[];
    final speedRunning = _busy && _operation == 'speed';
    return ListView(
      key: const PageStorageKey('speed-page'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _heading(
          'Which language finishes sooner?',
          'Calculate one image in Dart, Rust, C++ and C.',
        ),
        _settings(),
        const SizedBox(height: 12),
        if (speedRunning || _error) ...[
          RunBanner(
            title: _title,
            detail: _detail,
            progress: _progress,
            busy: speedRunning,
            error: _error,
          ),
          const SizedBox(height: 12),
        ],
        SpeedResults(
          key: _speedResultsKey,
          results: speedRunning ? const [] : selected,
          side: _side,
          workload: _workload,
        ),
        if (!speedRunning &&
            selected.isNotEmpty &&
            _preview != null &&
            _previewTask == _workload) ...[
          const SizedBox(height: 12),
          OutputPreview(
            workload: _workload,
            output: _preview!,
            input: _inputPreview,
          ),
        ],
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            // Expansion flags must not share the ListView's stored double offset.
            key: const PageStorageKey('speed-method-expansion'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            title: const Text(
              'How is this measured?',
              style: TextStyle(fontSize: 13),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: const [
              LabNote(
                'Each language uses the same algorithm and image size. We verify the output, warm up twice, then time seven runs in a shuffled order. Shorter bars mean less time. The median is the middle of the seven times.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _languagePicker() => LabCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Language to test',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final engine in Engine.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: engine == Engine.c ? 0 : 6),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 12,
                      ),
                      minimumSize: const Size(0, 44),
                      backgroundColor: _engine == engine
                          ? labAccent.withValues(alpha: 0.16)
                          : null,
                      side: BorderSide(
                        color: _engine == engine
                            ? labAccent
                            : labMuted.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _engine = engine),
                    child: Text(
                      engine.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: engineColors[engine],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _smoothnessPage() => ListView(
    key: const PageStorageKey('smoothness-page'),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    children: [
      _heading(
        'Does the animation pause?',
        'Keep the same task. Change where the work runs.',
      ),
      _settings(),
      const SizedBox(height: 12),
      _languagePicker(),
      const SizedBox(height: 12),
      SmoothnessResults(
        key: _smoothResultsKey,
        results: _jankResults,
        comparisonId: (_busy && _operation == 'animation') || _stopRequested
            ? _comparisonId
            : null,
        engine: _engine,
        workload: _workload,
        side: _side,
      ),
      const SizedBox(height: 12),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const PageStorageKey('smoothness-options-expansion'),
          title: const Text(
            'More test options',
            style: TextStyle(fontSize: 13),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: [
            const LabNote(
              'The main button tests an idle baseline, the UI thread, and a background isolate. Each measurement lasts 3 seconds.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('UI thread'),
                  selected: !_worker,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _worker = false),
                ),
                ChoiceChip(
                  label: const Text('Background'),
                  selected: _worker,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _worker = true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _guard(() => _jankCase(), operation: 'animation'),
              child: Text(
                'Run only ${_worker ? 'background' : 'UI thread'} · 3 sec',
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _guard(_compareAnimation, operation: 'animation'),
              child: const Text('Compare all four languages · ~35 sec'),
            ),
          ],
        ),
      ),
      if (_jankResults.isNotEmpty) _history(),
    ],
  );

  Widget _history() => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: const PageStorageKey('smoothness-history-expansion'),
      title: const Text(
        'Run history & detailed timings',
        style: TextStyle(fontSize: 13),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: [
        for (final result in _jankResults.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${result['engine']} · ${result['execution']} · ${result['workload']} · ${result['side']} px',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(result['animation_fps'] as num).toStringAsFixed(1)} fps · ${result['completed_jobs']} images completed\n95th-percentile gap: ${(result['gap_p95_ms'] as num).toStringAsFixed(1)} ms\nMedian job: ${(result['job_median_ms'] as num).toStringAsFixed(1)} ms\n95th-percentile UI build / raster: ${(result['ui_p95_ms'] as num).toStringAsFixed(1)} / ${(result['raster_p95_ms'] as num).toStringAsFixed(1)} ms',
                  style: const TextStyle(
                    color: labMuted,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _bottomAction() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_busy) ...[
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _operation == 'speed'
                        ? 'Checking and timing the image…'
                        : 'Watch the moving dot above',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (_operation == 'animation')
                  TextButton(
                    onPressed: _stopRequested
                        ? null
                        : () => setState(() => _stopRequested = true),
                    child: Text(_stopRequested ? 'Stopping…' : 'Stop'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: ValueKey(_page == 0 ? 'run-speed' : 'compare-smoothness'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onPressed: _busy
                  ? null
                  : () => _page == 0
                        ? _guard(() => _compute())
                        : _guard(_comparePair, operation: 'animation'),
              icon: Icon(
                _page == 0
                    ? Icons.play_arrow_rounded
                    : Icons.compare_arrows_rounded,
              ),
              label: Text(
                _page == 0 ? 'Compare speed' : 'Compare UI vs background',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _busy && _stopRequested
                ? 'Stops after the current 3-second measurement.'
                : _page == 0
                ? '${taskName(_workload)} · all four languages · 7 runs each'
                : '${_engine.label} · ${taskName(_workload)} · about 12 seconds',
            textAlign: TextAlign.center,
            style: const TextStyle(color: labMuted, fontSize: 10),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: labBackground,
      title: const Text(
        'Performance lab',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          key: const ValueKey('export-report'),
          onPressed: _report.isEmpty || _busy ? null : _export,
          tooltip: 'Copy full report',
          icon: const Icon(Icons.ios_share_rounded, size: 21),
        ),
        IconButton(
          onPressed: _showHelp,
          tooltip: 'How these tests work',
          icon: const Icon(Icons.help_outline_rounded, size: 22),
        ),
      ],
    ),
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.speed),
                    label: Text('Speed'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.animation),
                    label: Text('Smoothness'),
                  ),
                ],
                selected: {_page},
                showSelectedIcon: false,
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _page = value.first;
                        _error = false;
                        if (_page == 1) {
                          _animation.repeat();
                        } else {
                          _animation.stop();
                        }
                      }),
              ),
            ),
          ),
          if (_page == 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: LiveAnimation(
                animation: _animation,
                title: _busy || _error || _stopRequested
                    ? _title
                    : 'Watch the moving dot',
                detail: _busy || _error || _stopRequested
                    ? _detail
                    : 'It should move steadily. Heavy work can make it pause.',
                progress: _progress,
                measuring: _measuring,
              ),
            ),
          Expanded(child: _page == 0 ? _speedPage() : _smoothnessPage()),
        ],
      ),
    ),
    bottomNavigationBar: _bottomAction(),
  );
}

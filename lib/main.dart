import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bench/runner.dart';

void main() => runApp(const BenchApp());

class BenchApp extends StatelessWidget {
  const BenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart vs C++ vs Rust',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const BenchPage(),
    );
  }
}

const langColors = {
  Lang.dart: Color(0xFF0175C2),
  Lang.cpp: Color(0xFF9C27B0),
  Lang.rust: Color(0xFFE76F00),
};
const langNames = {Lang.dart: 'Dart', Lang.cpp: 'C++', Lang.rust: 'Rust'};

class BenchPage extends StatefulWidget {
  const BenchPage({super.key});

  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  final results = <String, Map<Lang, BenchResult>>{};
  String? running;
  bool busy = false;

  Future<void> _runAll() async {
    setState(() {
      busy = true;
      results.clear();
    });
    for (final b in benchmarks) {
      for (final lang in Lang.values) {
        setState(() => running = '${b.name} — ${langNames[lang]}');
        final r = await runBench(b, lang);
        setState(() => (results[b.name] ??= {})[lang] = r);
      }
    }
    setState(() {
      busy = false;
      running = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dart vs C++ vs Rust')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (kDebugMode)
            Card(
              color: theme.colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Debug mode: Dart runs in JIT with asserts and will look far '
                  'slower than reality. Use `flutter run --release` for real numbers.',
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: busy ? null : _runAll,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(busy ? 'Running: $running' : 'Run all benchmarks'),
          ),
          const SizedBox(height: 8),
          Text(
            'Median of $runsPerBench runs after 1 warm-up. Shorter bar = faster.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final b in benchmarks) _BenchCard(def: b, results: results[b.name]),
        ],
      ),
    );
  }
}

class _BenchCard extends StatelessWidget {
  const _BenchCard({required this.def, required this.results});
  final BenchDef def;
  final Map<Lang, BenchResult>? results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = results ?? const {};
    final maxMicros = r.values.fold<int>(1, (m, e) => e.medianMicros > m ? e.medianMicros : m);
    final dartTime = r[Lang.dart]?.medianMicros;
    final values = r.values.map((e) => e.value).toSet();
    final isCallTest = def.name == 'Call overhead';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(def.name, style: theme.textTheme.titleMedium),
            Text(def.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final lang in Lang.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 44, child: Text(langNames[lang]!)),
                    Expanded(
                      child: LayoutBuilder(builder: (context, c) {
                        final res = r[lang];
                        final frac = res == null ? 0.0 : res.medianMicros / maxMicros;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 14,
                            width: (c.maxWidth * frac).clamp(2, c.maxWidth),
                            decoration: BoxDecoration(
                              color: res == null
                                  ? theme.colorScheme.surfaceContainerHighest
                                  : langColors[lang],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(
                      width: 128,
                      child: Text(
                        _label(r[lang], dartTime, isCallTest),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                ),
              ),
            if (r.length == Lang.values.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  values.length == 1
                      ? '✓ All three returned the same result (${values.first})'
                      : '✗ Results differ: ${r.map((k, v) => MapEntry(langNames[k], v.value))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: values.length == 1 ? Colors.green : theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _label(BenchResult? res, int? dartTime, bool isCallTest) {
    if (res == null) return '—';
    final ms = res.medianMicros / 1000;
    if (isCallTest) {
      final nsPerCall = res.medianMicros * 1000 / callCount;
      return '${ms.toStringAsFixed(0)} ms · ${nsPerCall.toStringAsFixed(1)} ns/call';
    }
    final speedup = dartTime == null ? '' : ' · ${(dartTime / res.medianMicros).toStringAsFixed(1)}×';
    return '${ms.toStringAsFixed(1)} ms$speedup';
  }
}

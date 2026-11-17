import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'benchmark.dart';
import 'kernels.dart';

const labBackground = Color(0xFF0C1220);
const labSurface = Color(0xFF172133);
const labMuted = Color(0xFFA8B8D0);
const labAccent = Color(0xFF79E3C3);
const engineColors = {
  Engine.dart: Color(0xFF62BEFF),
  Engine.rust: Color(0xFFFFB781),
  Engine.cpp: Color(0xFFC9ACFF),
  Engine.c: Color(0xFF79E3C3),
};

String taskName(Workload workload) =>
    workload == Workload.blur ? 'Image blur' : 'Fractal';
String taskExplanation(Workload workload) => workload == Workload.blur
    ? 'Apply a blur filter to the same generated image.'
    : 'Calculate each pixel to draw the same fractal.';

class LabCard extends StatelessWidget {
  const LabCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: labSurface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class LabNote extends StatelessWidget {
  const LabNote(
    this.text, {
    super.key,
    this.icon = Icons.info_outline,
    this.color = labMuted,
  });
  final String text;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 12, height: 1.45),
        ),
      ),
    ],
  );
}

class TaskSettings extends StatelessWidget {
  const TaskSettings({
    super.key,
    required this.workload,
    required this.side,
    this.onTask,
    this.onSide,
  });
  final Workload workload;
  final int side;
  final ValueChanged<Workload>? onTask;
  final ValueChanged<int>? onSide;
  @override
  Widget build(BuildContext context) => LabCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Task',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            DropdownButton<int>(
              value: side,
              isDense: true,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(16),
              items: [
                for (final s in [256, 384, 512, 768])
                  DropdownMenuItem(
                    value: s,
                    child: Text(
                      '$s × $s',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: onSide == null ? null : (value) => onSide!(value!),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final task in Workload.values)
              ChoiceChip(
                label: Text(taskName(task)),
                avatar: Icon(
                  task == Workload.blur ? Icons.blur_on : Icons.auto_awesome,
                  size: 17,
                ),
                selected: workload == task,
                showCheckmark: false,
                onSelected: onTask == null ? null : (_) => onTask!(task),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          taskExplanation(workload),
          style: const TextStyle(color: labMuted, fontSize: 12, height: 1.4),
        ),
      ],
    ),
  );
}

class RunBanner extends StatelessWidget {
  const RunBanner({
    super.key,
    required this.title,
    required this.detail,
    required this.progress,
    this.busy = false,
    this.error = false,
  });
  final String title;
  final String detail;
  final ValueListenable<double?> progress;
  final bool busy;
  final bool error;
  @override
  Widget build(BuildContext context) => LabCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              error
                  ? Icons.error_outline
                  : busy
                  ? Icons.science_outlined
                  : Icons.check_circle_outline,
              color: error ? Colors.orangeAccent : labAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          style: const TextStyle(color: labMuted, fontSize: 12, height: 1.45),
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
      ],
    ),
  );
}

class SpeedResults extends StatelessWidget {
  const SpeedResults({
    super.key,
    required this.results,
    required this.side,
    required this.workload,
  });
  final List<Measurement> results;
  final int side;
  final Workload workload;
  @override
  Widget build(BuildContext context) {
    final ordered = results.toList()
      ..sort((a, b) => a.medianMs.compareTo(b.medianMs));
    final dartMs = results
        .where((m) => m.engine == Engine.dart)
        .firstOrNull
        ?.medianMs;
    final maximum = results.fold<double>(
      0.001,
      (v, m) => math.max(v, m.medianMs),
    );
    final fastest = ordered.firstOrNull;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  results.isEmpty
                      ? 'Four languages, same task'
                      : 'Time to finish one image',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (results.isNotEmpty)
                const Icon(Icons.verified_outlined, color: labAccent, size: 20),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            results.isEmpty
                ? 'Run the comparison to fill these rows.'
                : '${taskName(workload)} · $side × $side · lower is better',
            style: const TextStyle(color: labMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final engine in Engine.values)
            Builder(
              builder: (context) {
                final result = results
                    .where((m) => m.engine == engine)
                    .firstOrNull;
                final isFastest = result != null && result == fastest;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: engineColors[engine],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              engine.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isFastest)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                'QUICKEST',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: engineColors[engine],
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          Text(
                            result == null
                                ? '— ms'
                                : '${result.medianMs.toStringAsFixed(2)} ms',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              fontFeatures: [ui.FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: result == null ? 0 : result.medianMs / maximum,
                        minHeight: 5,
                        backgroundColor: labBackground,
                        color: engineColors[engine],
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          if (fastest != null && dartMs != null) ...[
            Text(
              fastest.engine == Engine.dart
                  ? 'Dart finished quickest in this run.'
                  : '${fastest.engine.label} was ${(dartMs / fastest.medianMs).toStringAsFixed(2)}× as fast as Dart in this run.',
              style: const TextStyle(
                color: labAccent,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            const LabNote(
              'All four produced exactly the same pixels.',
              icon: Icons.check_circle_outline,
              color: labAccent,
            ),
          ] else
            const LabNote(
              'The languages calculate the image. Flutter draws the interface.',
            ),
        ],
      ),
    );
  }
}

class OutputPreview extends StatelessWidget {
  const OutputPreview({
    super.key,
    required this.workload,
    required this.output,
    this.input,
  });
  final Workload workload;
  final ui.Image output;
  final ui.Image? input;
  @override
  Widget build(BuildContext context) => LabCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What was calculated?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (input != null) ...[
              Expanded(child: _image(input!, 'Input pattern')),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, color: labMuted, size: 18),
              ),
            ],
            Expanded(
              child: _image(
                output,
                workload == Workload.blur ? 'Blurred output' : 'Fractal output',
              ),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _image(ui.Image image, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 100,
          width: double.infinity,
          child: RawImage(image: image, fit: BoxFit.cover),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: labMuted, fontSize: 11)),
    ],
  );
}

class LiveAnimation extends StatelessWidget {
  const LiveAnimation({
    super.key,
    required this.animation,
    required this.title,
    required this.detail,
    required this.progress,
    this.measuring = false,
  });
  final Animation<double> animation;
  final String title;
  final String detail;
  final ValueListenable<double?> progress;
  final bool measuring;
  @override
  Widget build(BuildContext context) => LabCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: labAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              measuring ? 'MEASURING' : 'LIVE',
              style: const TextStyle(
                fontSize: 9,
                color: labAccent,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 60,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(painter: _MotionPainter(animation)),
          ),
        ),
        Text(
          detail,
          style: const TextStyle(color: labMuted, fontSize: 11, height: 1.4),
        ),
        if (measuring)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 3,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    ),
  );
}

class _MotionPainter extends CustomPainter {
  _MotionPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final width = math.max(0.0, size.width - 24);
    final paint = Paint()
      ..color = const Color(0xFF35435A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(12, y), Offset(12 + width, y), paint);
    for (var i = 0; i <= 12; i++) {
      canvas.drawCircle(Offset(12 + width * i / 12, y), 2, paint);
    }
    // One moving marker represents the Flutter animation, not four engines.
    for (var trail = 6; trail >= 0; trail--) {
      final t = animation.value - trail * 0.012;
      final x = 12 + width * (0.5 - 0.5 * math.cos(t * math.pi * 2));
      paint.color = labAccent.withValues(alpha: 1 - trail / 7);
      canvas.drawCircle(Offset(x, y), trail == 0 ? 7 : 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MotionPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class SmoothnessResults extends StatelessWidget {
  const SmoothnessResults({
    super.key,
    required this.results,
    required this.engine,
    required this.workload,
    required this.side,
    this.comparisonId,
  });
  final List<Map<String, Object>> results;
  final int? comparisonId;
  final Engine engine;
  final Workload workload;
  final int side;
  @override
  Widget build(BuildContext context) {
    final candidates = results.reversed.where(
      (r) =>
          r['engine'] == engine.label &&
          r['workload'] == workload.label &&
          r['side'] == side,
    );
    final batch = comparisonId ?? candidates.firstOrNull?['comparison_id'];
    final matching = candidates.where((r) => r['comparison_id'] == batch);
    final uiResult = matching.where((r) => r['execution'] == 'UI').firstOrNull;
    final workerResult = matching
        .where((r) => r['execution'] == 'worker')
        .firstOrNull;
    final baseline = results.reversed
        .where(
          (r) =>
              r['execution'] == 'baseline' &&
              r['comparison_id'] == batch &&
              r['workload'] == workload.label &&
              r['side'] == side,
        )
        .firstOrNull;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${engine.label}: animation smoothness',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            '${taskName(workload)} · $side × $side · higher fps is better',
            style: const TextStyle(color: labMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _row('UI thread', 'Animation and work share a thread', uiResult),
          const SizedBox(height: 16),
          _row('Background', 'Work runs on a separate isolate', workerResult),
          const SizedBox(height: 16),
          if (baseline != null)
            Text(
              'Without work: ${(baseline['animation_fps'] as num).toStringAsFixed(1)} fps · ${(baseline['refresh_hz'] as num).toStringAsFixed(0)} Hz display',
              style: const TextStyle(color: labMuted, fontSize: 11),
            ),
          if (uiResult != null && workerResult != null) ...[
            const SizedBox(height: 12),
            LabNote(
              (workerResult['animation_fps'] as num) >
                      (uiResult['animation_fps'] as num) * 1.15
                  ? 'Moving ${engine.label} work to the background kept the animation more responsive in this run.'
                  : 'Both modes had similar animation rates in this run. Try a larger image to increase the work.',
              icon: Icons.lightbulb_outline,
              color: labAccent,
            ),
          ] else ...[
            const SizedBox(height: 12),
            const LabNote(
              'Compare both modes to see whether moving the work helps.',
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'fps here measures animation updates, not GPU-presented frames.',
            style: TextStyle(color: labMuted, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, String subtitle, Map<String, Object>? result) {
    final fps = result?['animation_fps'] as num?;
    final hz = result?['refresh_hz'] as num?;
    final color = fps == null
        ? labMuted
        : fps >= hz! * 0.9
        ? labAccent
        : const Color(0xFFFFBA81);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: labMuted, fontSize: 11),
              ),
              if (result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${(result['late_percent'] as num).toStringAsFixed(1)}% long animation gaps',
                    style: TextStyle(color: color, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fps == null ? '—' : fps.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
            const Text('fps', style: TextStyle(color: labMuted, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

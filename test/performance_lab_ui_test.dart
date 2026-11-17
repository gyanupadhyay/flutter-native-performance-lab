import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../example/performance_lab/benchmark.dart';
import '../example/performance_lab/kernels.dart';
import '../example/performance_lab/lab_ui.dart';
import '../example/performance_lab/main.dart';

void main() {
  testWidgets(
    'scrolling and returning to a tab keeps expansion state separate',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PerformanceLab());
      await tester.pumpAndSettle();
      Finder pageScroll() => find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('How is this measured?'),
        300,
        scrollable: pageScroll(),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('How is this measured?'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Each language uses the same algorithm'),
        findsOneWidget,
      );

      for (var round = 0; round < 3; round++) {
        await tester.tap(find.text('Smoothness'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.scrollUntilVisible(
          find.text('More test options'),
          300,
          scrollable: pageScroll(),
        );
        await tester.ensureVisible(
          find.ancestor(
            of: find.text('More test options'),
            matching: find.byType(ExpansionTile),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('More test options').hitTestable(), findsOneWidget);
        await tester.tap(find.text('More test options'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Speed'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('How is this measured?'),
          200,
          scrollable: pageScroll(),
        );
        expect(
          find.textContaining('Each language uses the same algorithm'),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a fresh comparison never borrows a value from a previous run', (
    tester,
  ) async {
    final records = <Map<String, Object>>[
      for (final sample in [
        (1, 'UI', 25.0),
        (1, 'worker', 90.0),
        (2, 'UI', 30.0),
      ])
        {
          'engine': 'Dart',
          'workload': 'Image blur',
          'side': 512,
          'comparison_id': sample.$1,
          'execution': sample.$2,
          'animation_fps': sample.$3,
          'refresh_hz': 90.0,
          'late_percent': 0.0,
        },
    ];
    Widget page(int? comparisonId) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SmoothnessResults(
            results: records,
            engine: Engine.dart,
            workload: Workload.blur,
            side: 512,
            comparisonId: comparisonId,
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(null));
    expect(find.text('30.0'), findsOneWidget);
    expect(find.text('90.0'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    await tester.pumpWidget(page(3));
    expect(find.text('30.0'), findsNothing);
    expect(find.text('—'), findsNWidgets(2));
  });

  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('both views and help fit $size with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const PerformanceLab());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('run-speed')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Smoothness'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Watch the moving dot'), findsOneWidget);
      expect(find.byKey(const ValueKey('compare-smoothness')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('How these tests work'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Two questions. Two tests.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'speed result says which task ran and explains the winning ratio',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpeedResults(
                workload: Workload.blur,
                side: 512,
                results: [
                  Measurement(Engine.dart, Workload.blur, [40000], 1),
                  Measurement(Engine.c, Workload.blur, [20000], 1),
                  Measurement(Engine.cpp, Workload.blur, [21000], 1),
                  Measurement(Engine.rust, Workload.blur, [30000], 1),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Image blur · 512 × 512 · lower is better'),
        findsOneWidget,
      );
      expect(
        find.text('C was 2.00× as fast as Dart in this run.'),
        findsOneWidget,
      );
      expect(
        find.text('All four produced exactly the same pixels.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'smoothness comparisons exclude results from other configurations',
    (tester) async {
      final records = <Map<String, Object>>[
        for (final setup in [
          ('UI', 25.0, 512),
          ('worker', 90.0, 512),
          ('UI', 87.0, 256),
        ])
          {
            'engine': 'Dart',
            'workload': 'Image blur',
            'execution': setup.$1,
            'side': setup.$3,
            'animation_fps': setup.$2,
            'refresh_hz': 90.0,
            'late_percent': setup.$1 == 'UI' ? 90.0 : 0.0,
          },
      ];
      Widget page(Engine engine) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmoothnessResults(
              results: records,
              engine: engine,
              workload: Workload.blur,
              side: 512,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(Engine.dart));
      expect(find.text('25.0'), findsOneWidget);
      expect(find.text('90.0'), findsOneWidget);
      expect(find.text('87.0'), findsNothing);
      await tester.pumpWidget(page(Engine.rust));
      expect(find.text('25.0'), findsNothing);
      expect(find.text('90.0'), findsNothing);
      expect(find.text('—'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}

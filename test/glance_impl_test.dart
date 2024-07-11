import 'dart:async';
import 'dart:developer';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glance/glance.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance_impl.dart';
import 'package:glance/src/sampler.dart';

class FakeSampler implements Sampler {
  List<AggregatedNativeFrame> frames = [];

  bool isClose = false;

  @override
  void close() {
    isClose = true;
  }

  @override
  Future<List<AggregatedNativeFrame>> getSamples(
      List<int> timestampRange) async {
    return frames;
  }
}

class TestJankDetectedReporter extends JankDetectedReporter {
  TestJankDetectedReporter(this.onReport);
  final void Function(JankReport info) onReport;
  @override
  void report(JankReport info) {
    onReport(info);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Glance glance;
  late FakeSampler sampler;

  setUp(() {
    sampler = FakeSampler();
    glance = GlanceImpl.forTesting(sampler);
  });

  test('Should receive a report callback if stace traces are not empty',
      () async {
    final reportCompleter = Completer<JankReport>();
    await glance.start(
      config: GlanceConfiguration(
        jankThreshold: 1,
        reporters: [
          TestJankDetectedReporter((info) {
            if (!reportCompleter.isCompleted) {
              reportCompleter.complete(info);
            }
          }),
        ],
      ),
    );

    final onReportTimings = binding.platformDispatcher.onReportTimings;
    expect(onReportTimings, isNotNull);

    final frame = AggregatedNativeFrame(NativeFrame(
      pc: 540642472608,
      timestamp: Timeline.now,
      module: NativeModule(
        id: 1,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'hello',
      ),
    ));
    final frames = [frame];
    sampler.frames = frames;

    final rasterFinish = Timeline.now - 1000;
    final timing = FrameTiming(
      vsyncStart: rasterFinish - 4000,
      buildStart: rasterFinish - 3000,
      buildFinish: rasterFinish - 2000,
      rasterStart: rasterFinish - 1000,
      rasterFinish: rasterFinish,
      rasterFinishWallTime: rasterFinish,
    );
    final timings = [timing];
    onReportTimings!(timings);

    final expectedReport = JankReport(
        stackTrace: GlanceStackTraceImpl(frames), frameTimings: timings);

    final report = await reportCompleter.future;

    expect(report, equals(expectedReport));
  });

  test('Should not receive a report callback if stace traces are empty',
      () async {
    fakeAsync((async) {
      final reportCompleter = Completer<JankReport>();
      glance.start(
        config: GlanceConfiguration(
          jankThreshold: 1,
          reporters: [
            TestJankDetectedReporter((info) {
              if (!reportCompleter.isCompleted) {
                reportCompleter.complete(info);
              }
            }),
          ],
        ),
      );

      final onReportTimings = binding.platformDispatcher.onReportTimings;
      expect(onReportTimings, isNotNull);

      final rasterFinish = Timeline.now - 1000;
      final timing = FrameTiming(
        vsyncStart: rasterFinish - 4000,
        buildStart: rasterFinish - 3000,
        buildFinish: rasterFinish - 2000,
        rasterStart: rasterFinish - 1000,
        rasterFinish: rasterFinish,
        rasterFinishWallTime: rasterFinish,
      );
      final timings = [timing];
      onReportTimings!(timings);

      expect(reportCompleter.future.timeout(const Duration(seconds: 5)),
          throwsA(isA<TimeoutException>()));

      async.elapse(const Duration(seconds: 5));
    });
  });

  test('Should not receive a report callback if stace traces are the same',
      () async {
    fakeAsync((async) async {
      final reportCompleter = Completer<JankReport>();
      int reportTimeCount = 0;
      final secondTimeReportCompleter = Completer<void>();
      glance.start(
        config: GlanceConfiguration(
          jankThreshold: 1,
          reporters: [
            TestJankDetectedReporter((info) {
              reportTimeCount++;

              if (!reportCompleter.isCompleted) {
                reportCompleter.complete(info);
              }

              if (reportTimeCount == 2 &&
                  !secondTimeReportCompleter.isCompleted) {
                secondTimeReportCompleter.complete();
              }
            }),
          ],
        ),
      );

      final onReportTimings = binding.platformDispatcher.onReportTimings;
      expect(onReportTimings, isNotNull);

      final frame = AggregatedNativeFrame(NativeFrame(
        pc: 540642472608,
        timestamp: Timeline.now,
        module: NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        ),
      ));
      final frames = [frame];
      sampler.frames = frames;

      final rasterFinish = Timeline.now - 1000;
      final timing = FrameTiming(
        vsyncStart: rasterFinish - 4000,
        buildStart: rasterFinish - 3000,
        buildFinish: rasterFinish - 2000,
        rasterStart: rasterFinish - 1000,
        rasterFinish: rasterFinish,
        rasterFinishWallTime: rasterFinish,
      );
      final timings = [timing];
      onReportTimings!(timings);
      onReportTimings(timings);

      final expectedReport = JankReport(
          stackTrace: GlanceStackTraceImpl(frames), frameTimings: timings);
      final report = await reportCompleter.future;
      expect(report, equals(expectedReport));

      expect(
          secondTimeReportCompleter.future.timeout(const Duration(seconds: 5)),
          throwsA(isA<TimeoutException>()));

      async.elapse(const Duration(seconds: 5));
    });
  });

  test('Call Sampler.close after calling end', () async {
    glance.start();
    await glance.end();

    expect(sampler.isClose, isTrue);
  });

  test('Should not receive a report callback after calling end', () {
    fakeAsync((async) async {
      // Add a TimingsCallback to initialize the `PlatformDispatcher.onReportTimings`
      binding.addTimingsCallback((timings) {});
      final onReportTimings = binding.platformDispatcher.onReportTimings;

      final reportCompleter = Completer<JankReport>();
      glance.start(
        config: GlanceConfiguration(
          jankThreshold: 1,
          reporters: [
            TestJankDetectedReporter((info) {
              if (!reportCompleter.isCompleted) {
                reportCompleter.complete(info);
              }
            }),
          ],
        ),
      );

      await glance.end();

      final frame = AggregatedNativeFrame(NativeFrame(
        pc: 540642472608,
        timestamp: Timeline.now,
        module: NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        ),
      ));
      final frames = [frame];
      sampler.frames = frames;

      final rasterFinish = Timeline.now - 1000;
      final timing = FrameTiming(
        vsyncStart: rasterFinish - 4000,
        buildStart: rasterFinish - 3000,
        buildFinish: rasterFinish - 2000,
        rasterStart: rasterFinish - 1000,
        rasterFinish: rasterFinish,
        rasterFinishWallTime: rasterFinish,
      );
      final timings = [timing];
      onReportTimings!(timings);

      expect(reportCompleter.future.timeout(const Duration(seconds: 5)),
          throwsA(isA<TimeoutException>()));

      async.elapse(const Duration(seconds: 5));
    });
  });

  test('GlanceStackTraceImpl.toString', () {
    final frame1 = AggregatedNativeFrame(NativeFrame(
      pc: 540642472608,
      timestamp: Timeline.now,
      module: NativeModule(
        id: 1,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'hello',
      ),
    ));
    final frame2 = AggregatedNativeFrame(NativeFrame(
      pc: 540642472607,
      timestamp: Timeline.now,
      module: NativeModule(
        id: 2,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'world',
      ),
    ));
    final stackTrace = GlanceStackTraceImpl([frame1, frame2]);

    const expectedStackTrace = '''
$kGlaceStackTraceHeaderLine
#0   540641718272 540642472608 libapp.so
#1   540641718272 540642472607 libapp.so
''';

    expect(stackTrace.toString(), expectedStackTrace);
  });
}

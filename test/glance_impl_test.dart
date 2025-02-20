import 'dart:async';
import 'dart:developer';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glance/glance.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/glance_impl.dart';
import 'package:glance/src/sampler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';

class TestGlanceWidgetBindingMixin extends WidgetsFlutterBinding
    with GlanceWidgetBindingMixin {}

class FakeSampler implements Sampler {
  List<AggregatedNativeFrame> frames = [];

  bool isClose = false;

  @override
  void close() {
    isClose = true;
  }

  @override
  Future<List<AggregatedNativeFrame>> getSamples(
    List<int> timestampRange,
  ) async {
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
  final glanceWidgetBinding = GlanceWidgetBinding.ensureInitialized();

  late Glance glance;
  late FakeSampler sampler;

  setUp(() {
    sampler = FakeSampler();
    glance = GlanceImpl.forTesting(sampler);
  });

  group('GlanceImpl.create', () {
    test('return GlanceImpl', () {
      final instance = GlanceImpl.create(false);
      expect(instance, isInstanceOf<GlanceImpl>());
    });

    test('return GlanceNoOpImpl', () {
      final instance = GlanceImpl.create(true);
      expect(instance, isInstanceOf<GlanceNoOpImpl>());
    });
  });

  group('GlanceWidgetBindingMixin', () {
    test(
      'call onCheckJank when calling traceFunctionCall if it is in SchedulerPhase.idle',
      () {
        bool onCheckJankCalled = false;
        glanceWidgetBinding.onCheckJank = (int start, int end) {
          onCheckJankCalled = true;
        };

        glanceWidgetBinding.traceFunctionCall(() {});
        expect(onCheckJankCalled, isTrue);
      },
    );

    test(
      'do not call onCheckJank when calling traceFunctionCall if it is not in SchedulerPhase.idle',
      () {
        bool onCheckJankCalled = false;
        glanceWidgetBinding.onCheckJank = (int start, int end) {
          onCheckJankCalled = true;
        };

        glanceWidgetBinding.handleBeginFrame(const Duration());
        glanceWidgetBinding.traceFunctionCall(() {});
        expect(onCheckJankCalled, isFalse);

        // Let the `schedulerPhase` to be `SchedulerPhase.idle`
        glanceWidgetBinding.handleDrawFrame();
      },
    );

    test('called onCheckJank after calling handleDrawFrame', () {
      bool onCheckJankCalled = false;
      glanceWidgetBinding.onCheckJank = (int start, int end) {
        onCheckJankCalled = true;
      };

      glanceWidgetBinding.handleBeginFrame(const Duration());
      glanceWidgetBinding.handleDrawFrame();
      expect(onCheckJankCalled, isTrue);
    });

    test('called onCheckJank after calling handlePointerEvent', () {
      bool onCheckJankCalled = false;
      glanceWidgetBinding.onCheckJank = (int start, int end) {
        onCheckJankCalled = true;
      };

      glanceWidgetBinding.handlePointerEvent(const PointerAddedEvent());
      expect(onCheckJankCalled, isTrue);
    });

    test('called onCheckJank after calling handleMetricsChanged', () {
      bool onCheckJankCalled = false;
      glanceWidgetBinding.onCheckJank = (int start, int end) {
        onCheckJankCalled = true;
      };

      glanceWidgetBinding.handleMetricsChanged();
      expect(onCheckJankCalled, isTrue);
    });

    test('called onCheckJank after calling handleTextScaleFactorChanged', () {
      bool onCheckJankCalled = false;
      glanceWidgetBinding.onCheckJank = (int start, int end) {
        onCheckJankCalled = true;
      };

      glanceWidgetBinding.handleTextScaleFactorChanged();
      expect(onCheckJankCalled, isTrue);
    });

    test(
      'called onCheckJank after calling handlePlatformBrightnessChanged',
      () {
        bool onCheckJankCalled = false;
        glanceWidgetBinding.onCheckJank = (int start, int end) {
          onCheckJankCalled = true;
        };

        glanceWidgetBinding.handlePlatformBrightnessChanged();
        expect(onCheckJankCalled, isTrue);
      },
    );

    test('called onCheckJank after calling dispatchLocalesChanged', () {
      bool onCheckJankCalled = false;
      glanceWidgetBinding.onCheckJank = (int start, int end) {
        onCheckJankCalled = true;
      };

      glanceWidgetBinding.dispatchLocalesChanged([]);
      expect(onCheckJankCalled, isTrue);
    });

    test(
      'called onCheckJank after calling handleAccessibilityFeaturesChanged',
      () {
        bool onCheckJankCalled = false;
        glanceWidgetBinding.onCheckJank = (int start, int end) {
          onCheckJankCalled = true;
        };

        glanceWidgetBinding.handleAccessibilityFeaturesChanged();
        expect(onCheckJankCalled, isTrue);
      },
    );

    test(
      'called onCheckJank when received platform message in MethodChannel.setMethodCallHandler',
      () async {
        final onCheckJankCalledCompleter = Completer<bool>();
        glanceWidgetBinding.onCheckJank = (int start, int end) {
          onCheckJankCalledCompleter.complete(true);
        };

        const channelName = 'my_channel';
        const methodChannel = MethodChannel(channelName);
        final methodCallHandlerCalledCompleter = Completer<bool>();
        methodChannel.setMethodCallHandler((methodCall) async {
          methodCallHandlerCalledCompleter.complete(true);
          return true;
        });

        // Simulate a `MethodChannel` call from platform
        const StandardMethodCodec codec = StandardMethodCodec();
        final ByteData data = codec.encodeMethodCall(
          const MethodCall('my_method'),
        );

        await glanceWidgetBinding.defaultBinaryMessenger
        // ignore: deprecated_member_use
        .handlePlatformMessage('my_channel', data, (ByteData? data) {});
        expect((await onCheckJankCalledCompleter.future), isTrue);
        expect((await methodCallHandlerCalledCompleter.future), isTrue);
      },
    );
  });

  test(
    'Should receive a report callback if stace traces are not empty',
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

      final onCheckJank = glanceWidgetBinding.onCheckJank;
      expect(onCheckJank, isNotNull);

      final frame = AggregatedNativeFrame(
        NativeFrame(
          pc: 540642472608,
          timestamp: Timeline.now,
          module: NativeModule(
            id: 1,
            path: 'libapp.so',
            baseAddress: 540641718272,
            symbolName: 'hello',
          ),
        ),
      );
      final frames = [frame];
      sampler.frames = frames;

      final now = Timeline.now - 2000;
      onCheckJank!(now - 3000, now);

      final expectedReport = JankReport(
        stackTrace: GlanceStackTraceImpl(
          frames,
          const DartStackTraceInfo(0, []),
        ),
      );

      final report = await reportCompleter.future;

      expect(report, equals(expectedReport));
    },
  );

  test(
    'Should not receive a report callback if stace traces are empty',
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

        final onCheckJank = glanceWidgetBinding.onCheckJank;
        expect(onCheckJank, isNotNull);

        final now = Timeline.now - 2000;
        onCheckJank!(now - 3000, now);

        expect(
          reportCompleter.future.timeout(const Duration(seconds: 5)),
          throwsA(isA<TimeoutException>()),
        );

        async.elapse(const Duration(seconds: 5));
      });
    },
  );

  test(
    'Should not receive a report callback if stace traces are the same',
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

        final onCheckJank = glanceWidgetBinding.onCheckJank;
        expect(onCheckJank, isNotNull);

        final frame = AggregatedNativeFrame(
          NativeFrame(
            pc: 540642472608,
            timestamp: Timeline.now,
            module: NativeModule(
              id: 1,
              path: 'libapp.so',
              baseAddress: 540641718272,
              symbolName: 'hello',
            ),
          ),
        );
        final frames = [frame];
        sampler.frames = frames;

        final now = Timeline.now - 2000;
        onCheckJank!(now - 3000, now);

        final expectedReport = JankReport(
          stackTrace: GlanceStackTraceImpl(
            frames,
            const DartStackTraceInfo(0, []),
          ),
        );
        final report = await reportCompleter.future;
        expect(report, equals(expectedReport));

        expect(
          secondTimeReportCompleter.future.timeout(const Duration(seconds: 5)),
          throwsA(isA<TimeoutException>()),
        );

        async.elapse(const Duration(seconds: 5));
      });
    },
  );

  test('Call Sampler.close after calling end', () async {
    glance.start();
    await glance.end();

    expect(sampler.isClose, isTrue);
  });

  test('Should not receive a report callback after calling end', () {
    fakeAsync((async) async {
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

      {
        final onCheckJank = glanceWidgetBinding.onCheckJank;
        expect(onCheckJank, isNotNull);
      }

      await glance.end();

      {
        final onCheckJank = glanceWidgetBinding.onCheckJank;
        expect(onCheckJank, isNull);
      }

      async.elapse(const Duration(seconds: 5));
    });
  });

  group('GlanceStackTraceImpl', () {
    test('GlanceStackTraceImpl.toString', () {
      final frame1 = AggregatedNativeFrame(
        NativeFrame(
          pc: 110,
          timestamp: Timeline.now,
          module: NativeModule(
            id: 1,
            path: 'libapp.so',
            baseAddress: 540641718272,
            symbolName: 'hello',
          ),
        ),
      );
      final frame2 = AggregatedNativeFrame(
        NativeFrame(
          pc: 120,
          timestamp: Timeline.now,
          module: NativeModule(
            id: 2,
            path: 'libapp.so',
            baseAddress: 540641718272,
            symbolName: 'world',
          ),
        ),
      );
      const isolateInstructions = 100;
      final dartStackTraceHeaderLines = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 3081, tid: 6164033536, name io.flutter.1.ui
os: ios arch: arm64 comp: no sim: no
build_id: 'a8a967193ee33ac7a4852e7160590972'
isolate_dso_base: 1016b8000, vm_dso_base: 1016b8000
isolate_instructions: 100, vm_instructions: 1016bc000
'''.trim().split('\n');
      DartStackTraceInfo dartStackTraceInfo = DartStackTraceInfo(
        isolateInstructions,
        dartStackTraceHeaderLines,
      );
      final stackTrace = GlanceStackTraceImpl([
        frame1,
        frame2,
      ], dartStackTraceInfo);

      const expectedStackTrace = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 3081, tid: 6164033536, name io.flutter.1.ui
os: ios arch: arm64 comp: no sim: no
build_id: 'a8a967193ee33ac7a4852e7160590972'
isolate_dso_base: 1016b8000, vm_dso_base: 1016b8000
isolate_instructions: 100, vm_instructions: 1016bc000
    #00 abs 000000000000006e _kDartIsolateSnapshotInstructions+0xa
    #01 abs 0000000000000078 _kDartIsolateSnapshotInstructions+0x14
''';

      expect(stackTrace.toString(), expectedStackTrace);
    });

    test(
      'GlanceStackTraceImpl.toString when dart stack trace infos are empty',
      () {
        final frame1 = AggregatedNativeFrame(
          NativeFrame(
            pc: 110,
            timestamp: Timeline.now,
            module: NativeModule(
              id: 1,
              path: 'libapp.so',
              baseAddress: 540641718272,
              symbolName: 'hello',
            ),
          ),
        );
        final frame2 = AggregatedNativeFrame(
          NativeFrame(
            pc: 120,
            timestamp: Timeline.now,
            module: NativeModule(
              id: 2,
              path: 'libapp.so',
              baseAddress: 540641718272,
              symbolName: 'world',
            ),
          ),
        );
        DartStackTraceInfo dartStackTraceInfo = const DartStackTraceInfo(0, []);
        final stackTrace = GlanceStackTraceImpl([
          frame1,
          frame2,
        ], dartStackTraceInfo);

        const expectedStackTrace = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
    #00 abs 000000000000006e _kDartIsolateSnapshotInstructions
    #01 abs 0000000000000078 _kDartIsolateSnapshotInstructions
''';

        expect(stackTrace.toString(), expectedStackTrace);
      },
    );

    test('Able to parseDartStackTraceInfo', () async {
      final fakeDartStackTrace =
          '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 3081, tid: 6164033536, name io.flutter.1.ui
os: ios arch: arm64 comp: no sim: no
build_id: 'a8a967193ee33ac7a4852e7160590972'
isolate_dso_base: 1016b8000, vm_dso_base: 1016b8000
isolate_instructions: 100, vm_instructions: 1016bc000
    #00 abs 000000000000006e _kDartIsolateSnapshotInstructions+0xa
    #01 abs 0000000000000078 _kDartIsolateSnapshotInstructions+0x14
'''.trim();

      final info = (glance as GlanceImpl).parseDartStackTraceInfo(
        fakeDartStackTrace,
      );
      expect(info!.isolateInstructions, 256);

      final expectedDartStackTraceHeaderLines = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 3081, tid: 6164033536, name io.flutter.1.ui
os: ios arch: arm64 comp: no sim: no
build_id: 'a8a967193ee33ac7a4852e7160590972'
isolate_dso_base: 1016b8000, vm_dso_base: 1016b8000
isolate_instructions: 100, vm_instructions: 1016bc000
'''.trim().split('\n');
      expect(
        info.dartStackTraceHeaderLines,
        equals(expectedDartStackTraceHeaderLines),
      );
    });

    test('check equals', () {
      final frame1 = AggregatedNativeFrame(
        NativeFrame(
          pc: 110,
          timestamp: Timeline.now,
          module: NativeModule(
            id: 1,
            path: 'libapp.so',
            baseAddress: 540641718272,
            symbolName: 'hello',
          ),
        ),
      );
      final frame2 = AggregatedNativeFrame(
        NativeFrame(
          pc: 120,
          timestamp: Timeline.now,
          module: NativeModule(
            id: 2,
            path: 'libapp.so',
            baseAddress: 540641718272,
            symbolName: 'world',
          ),
        ),
      );
      DartStackTraceInfo dartStackTraceInfo = const DartStackTraceInfo(0, []);
      final stackTrace1 = GlanceStackTraceImpl([
        frame1,
        frame2,
      ], dartStackTraceInfo);
      final stackTrace2 = GlanceStackTraceImpl([
        frame1,
        frame2,
      ], dartStackTraceInfo);

      expect(stackTrace1, equals(stackTrace2));
    });
  });
}

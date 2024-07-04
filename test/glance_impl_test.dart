import 'dart:async';
import 'dart:developer';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:glance/glance.dart';
import 'package:glance/glance_platform_interface.dart';
import 'package:glance/glance_method_channel.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/glance_impl.dart';
import 'package:glance/src/sampler.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// class MockGlancePlatform
//     with MockPlatformInterfaceMixin
//     implements GlancePlatform {

//   @override
//   Future<String?> getPlatformVersion() => Future.value('42');
// }

class FakeSampler implements Sampler {
  List<AggregatedNativeFrame> frames = [];

  @override
  void close() {}

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

  group('start', () {
    test('should receive a report callback if samples are not empty', () async {
      final reportCompleter = Completer<JankReport>();
      // late JankReport report;
      await glance.start(
        config: GlanceConfiguration(
          jankThreshold: 1,
          reporters: [
            TestJankDetectedReporter((info) {
              // report = info;

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

    test('should not receive a report callback if samples are empty', () async {
      String reportInString = '';
      late List<FrameTiming> infoTimings;
      await glance.start(
        config: GlanceConfiguration(reporters: [
          TestJankDetectedReporter((info) {
            infoTimings = info.frameTimings;
          }),
        ]),
      );

      final onReportTimings = binding.platformDispatcher.onReportTimings;
      expect(onReportTimings, isNotNull);

      final rasterFinish = Timeline.now - 10;
      final timing = FrameTiming(
        vsyncStart: rasterFinish - 25,
        buildStart: rasterFinish - 20,
        buildFinish: rasterFinish - 15,
        rasterStart: rasterFinish - 10,
        rasterFinish: rasterFinish,
        rasterFinishWallTime: rasterFinish,
      );
      onReportTimings!([timing]);

      expect(infoTimings, equals([timing]));
    });
  });

  test('end', () {});

  // test('getPlatformVersion', () async {
  //   Glance glancePlugin = Glance();
  //   MockGlancePlatform fakePlatform = MockGlancePlatform();
  //   GlancePlatform.instance = fakePlatform;

  //   expect(await glancePlugin.getPlatformVersion(), '42');
  // });
}

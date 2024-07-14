import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance.dart';
import 'package:glance/src/sampler.dart';

class GlanceImpl implements Glance {
  GlanceImpl();

  @visibleForTesting
  GlanceImpl.forTesting(Sampler sampler) : _sampler = sampler;

  Sampler? _sampler;

  TimingsCallback? _timingsCallback;

  late List<GlanceReporter> reporters;

  bool _started = false;

  GlanceStackTrace? _previousStackTrace;

  @override
  Future<void> start(
      {GlanceConfiguration config = const GlanceConfiguration()}) async {
    if (_started) {
      return;
    }

    _started = true;
    final jankThreshold = config.jankThreshold;
    reporters = List.of(config.reporters, growable: false);

    _sampler ??= await Sampler.create(SamplerConfig(
      jankThreshold: jankThreshold,
      modulePathFilters: config.modulePathFilters,
      sampleRateInMilliseconds: config.sampleRateInMilliseconds,
    ));

    _timingsCallback ??= (List<FrameTiming> timings) {
      if (_sampler == null) {
        return;
      }
      final jankTimings = <FrameTiming>[];
      for (int i = 0; i < timings.length; ++i) {
        final FrameTiming timing = timings[i];

        final totalSpan = timing.totalSpan.inMilliseconds;
        if (totalSpan > jankThreshold) {
          jankTimings.add(timing);
        }
      }

      if (jankTimings.isNotEmpty) {
        _report(jankTimings, 0);
      }
    };

    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);
  }

  @override
  Future<void> end() async {
    if (!_started) {
      return;
    }
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback!);
    _timingsCallback = null;
    _sampler?.close();
  }

  Future<void> _report(List<FrameTiming> timings, int index) async {
    final timestampRange = [
      timings.first.timestampInMicroseconds(FramePhase.vsyncStart),
      timings.last.timestampInMicroseconds(FramePhase.rasterFinish),
    ];

    assert(_sampler != null);
    final frames = await _sampler!.getSamples(timestampRange);
    if (frames.isEmpty) {
      return;
    }

    final straceTrace = GlanceStackTraceImpl(frames);
    if (straceTrace == _previousStackTrace) {
      return;
    }

    final report = JankReport(
      stackTrace: straceTrace,
      frameTimings: timings,
    );

    _previousStackTrace = straceTrace;

    for (final reporter in reporters) {
      reporter.report(report);
    }
  }
}

class GlanceStackTraceImpl implements GlanceStackTrace {
  GlanceStackTraceImpl(this.stackTraces);
  final List<AggregatedNativeFrame> stackTraces;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    return other is GlanceStackTraceImpl &&
        listEquals(stackTraces, other.stackTraces);
  }

  @override
  int get hashCode => Object.hashAll(stackTraces);

  /// Output stack traces with format:
  /// *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
  /// #0   <base_addr> <pc> <module_path>
  /// #1   <base_addr> <pc> <module_path>
  @override
  String toString() {
    final stringBuffer = StringBuffer();
    stringBuffer.writeln(kGlaceStackTraceHeaderLine);
    for (int i = 0; i < stackTraces.length; ++i) {
      final stackTrace = stackTraces[i];
      final frame = stackTrace.frame;
      // final occurTimes = stackTrace.occurTimes;
      stringBuffer
          .write('#${i.toString().padRight(3, kGlaceStackTraceLineSpilt)}');
      stringBuffer.write(kGlaceStackTraceLineSpilt);
      stringBuffer.write(frame.module!.baseAddress);
      stringBuffer.write(kGlaceStackTraceLineSpilt);
      stringBuffer.write(frame.pc);
      // stringBuffer.write(kGlaceStackTraceLineSpilt);
      // stringBuffer.write(occurTimes);
      stringBuffer.write(kGlaceStackTraceLineSpilt);
      stringBuffer.write(frame.module!.path); // Is it necessary?
      stringBuffer.writeln();
    }

    return stringBuffer.toString();
  }
}

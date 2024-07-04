import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance.dart';
import 'package:glance/src/sampler.dart';

class GlanceImpl implements Glance {
  GlanceImpl();

  @visibleForTesting
  GlanceImpl.forTesting(Sampler sampler) : _sampleThread = sampler;

  Sampler? _sampleThread;

  TimingsCallback? _timingsCallback;

  // final List<JankCallback> _jankCallbacks = [];
  // final List<SlowFunctionsDetectedCallback>
  //     _slowFunctionsDetectedCallbackCallbacks = [];

  late List<GlanceReporter> reporters;

  bool _started = false;

  JankReport? _previousReport;

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

    // final binding = GlanceWidgetBinding.ensureInitialized();
    // binding.setOnHandleDrawFrameEndCallback(
    //     (int beginFrameTimeInMillis, int drawFrameTimeInMillis) {
    //   final diff = drawFrameTimeInMillis - beginFrameTimeInMillis;
    //   print('diff: $diff');
    //   if (diff > jankThreshold) {
    //     // report jank
    //     // _report(beginFrameTimeInMillis, drawFrameTimeInMillis);
    //   }
    //   _report(beginFrameTimeInMillis, drawFrameTimeInMillis);
    // });

    _sampleThread ??= await Sampler.create(SamplerConfig(
      jankThreshold: jankThreshold,
      modulePathFilters: config.modulePathFilters,
      sampleRateInMilliseconds: config.sampleRateInMilliseconds,
    ));
    // _sampleThread?.addSlowFunctionsDetectedCallback((info) {
    //   for (final callback
    //       in List.from(_slowFunctionsDetectedCallbackCallbacks)) {
    //     callback(info);
    //   }
    // });

    // if (_timingsCallback != null) {
    //   SchedulerBinding.instance.removeTimingsCallback(_timingsCallback!);
    // }

    _timingsCallback ??= (List<FrameTiming> timings) {
      if (_sampleThread == null) {
        return;
      }
      // int now = DateTime.now().microsecondsSinceEpoch;
      final jankTimings = <FrameTiming>[];
      for (int i = 0; i < timings.length; ++i) {
        final FrameTiming timing = timings[i];
        // print(
        //     'FramePhase.vsyncStart: ${timing.timestampInMicroseconds(FramePhase.vsyncStart)}, FramePhase.rasterFinish: ${timing.timestampInMicroseconds(FramePhase.rasterFinish)}');
        // print(
        //     'timing.buildDuration: ${timing.buildDuration.inMilliseconds}, timing.rasterDuration: ${timing.rasterDuration.inMilliseconds}, timing.totalSpan: ${timing.totalSpan.inMilliseconds}');
        //   print(
        //       'timing.timestampInMicroseconds(FramePhase.rasterFinish): ${timing.timestampInMicroseconds(FramePhase.rasterFinish)}');
        //   print(
        //       'timing.timestampInMicroseconds(FramePhase.buildStart): ${timing.timestampInMicroseconds(FramePhase.buildStart)}');
        // final diff = timing.timestampInMicroseconds(FramePhase.rasterFinish) -
        //     timing.timestampInMicroseconds(FramePhase.buildStart);
        final totalSpan = timing.totalSpan.inMilliseconds;
        if (totalSpan > jankThreshold) {
          // report jank
          // _report(timings, i);
          // break;

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
    _sampleThread?.close();
  }

  // Future<void> _report(int startTimestamp, int endTimestamp) async {
  //   if (_sampleThread == null) {
  //     return;
  //   }
  //   // Report the nearest 3 timings if possiable.
  //   // int preIndex = index - 1;
  //   // int nextIndex = index + 1;
  //   // List<FrameTiming> reportTimings = [];
  //   // if (preIndex >= 0) {
  //   //   reportTimings.add(timings[preIndex]);
  //   // }
  //   // reportTimings.add(timings[index]);
  //   // if (nextIndex < timings.length) {
  //   //   reportTimings.add(timings[nextIndex]);
  //   // }
  //   // assert(reportTimings.isNotEmpty);

  //   // // Request stacktraces
  //   final timestampRange = [startTimestamp, endTimestamp];

  //   assert(_sampleThread != null);
  //   final frames = await _sampleThread!.getSamples(timestampRange);
  //   final stacktrace = JankReport._(
  //     stackTraces: frames,
  //     jankDuration: Duration(milliseconds: endTimestamp - startTimestamp),
  //   );

  //   final callbacks = List.from(_jankCallbacks);
  //   for (final callback in callbacks) {
  //     callback(stacktrace);
  //   }
  // }

  Future<void> _report(List<FrameTiming> timings, int index) async {
    // Report the nearest 3 timings if possiable.
    // int preIndex = index - 1;
    // int nextIndex = index + 1;
    // List<FrameTiming> reportTimings = timings;
    // if (preIndex >= 0) {
    //   reportTimings.add(timings[preIndex]);
    // }
    // reportTimings.add(timings[index]);
    // if (nextIndex < timings.length) {
    //   reportTimings.add(timings[nextIndex]);
    // }
    // assert(reportTimings.isNotEmpty);

    // Request stacktraces
    final timestampRange = [
      timings.first.timestampInMicroseconds(FramePhase.vsyncStart),
      timings.last.timestampInMicroseconds(FramePhase.rasterFinish),
    ];

    assert(_sampleThread != null);
    final frames = await _sampleThread!.getSamples(timestampRange);
    if (frames.isEmpty) {
      return;
    }

    // TODO(littlegnal): Check if the same stack trace, if yes, do not report again
    final straceTrace = GlanceStackTraceImpl(frames);
    if (straceTrace == _previousStackTrace) {
      return;
    }

    final report = JankReport(
      stackTrace: straceTrace,
      frameTimings: timings,
    );

    _previousStackTrace = straceTrace;

    // final callbacks = List.from(_jankCallbacks);
    // for (final callback in callbacks) {
    //   callback(stacktrace);
    // }

    for (final reporter in reporters) {
      reporter.report(report);
    }
  }

  // void addJankCallback(JankCallback callback) {
  //   _jankCallbacks.add(callback);
  // }

  // void addSlowFunctionsDetectedCallback(
  //     SlowFunctionsDetectedCallback callback) {
  //   _slowFunctionsDetectedCallbackCallbacks.add(callback);
  // }
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

  // static const _headerLine =
  //     '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***';
  // static const _spilt = ' ';
  // static const _baseAddrKey = 'base_addr';
  // static const _pcKey = 'pc';

  /// *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
  /// #00  0000000000000640 0000000000042f89 30  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   exec_time 30
  /// #00  0000000000000640 0000000000042f89 30  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   exec_time 30
  /// #00  0000000000000640 0000000000042f89 30  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   exec_time 30
  /// #00  0000000000000640 0000000000042f89 30  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   exec_time 30
  /// #01  base_addr 0000000000000640  pc 0000000000000640  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::runCrashThread())         ~30
  /// #02  base_addr 0000000000000640  pc 0000000000065a3b  /system/lib/libc.so (__pthread_start(void*))                                                   ~30
  /// #03  base_addr 0000000000000640  pc 000000000001e4fd  /system/lib/libc.so (__start_thread)
  /// *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
  @override
  String toString() {
    final stringBuffer = StringBuffer();
    stringBuffer.writeln(kGlaceStackTraceHeaderLine);
    for (int i = 0; i < stackTraces.length; ++i) {
      final stackTrace = stackTraces[i];
      final frame = stackTrace.frame;
      final occurTimes = stackTrace.occurTimes;
      stringBuffer.write('#${i.toString().padLeft(3, '0')}');
      stringBuffer.write(kGlaceStackTraceLineSpilt);
      stringBuffer.write(frame.module!.baseAddress);
      stringBuffer.write(kGlaceStackTraceLineSpilt);
      stringBuffer.write(frame.pc);
      stringBuffer.write(kGlaceStackTraceLineSpilt);
      stringBuffer.write(occurTimes);
      stringBuffer.write(kGlaceStackTraceLineSpilt);
      stringBuffer.write(frame.module!.path); // Is it necessary?
      stringBuffer.writeln();
    }

    // stackTraces.map((e) {
    //     final frame = e.frame;
    //     final spent = e.timestampInMacros;
    //     return {
    //       "pc": frame.pc.toString(),
    //       "timestamp": frame.timestamp,
    //       if (frame.module != null)
    //         "baseAddress": frame.module!.baseAddress.toString(),
    //       if (frame.module != null) "path": frame.module!.path,
    //       'spent': spent,
    //     };
    //   }).toList()

    return stringBuffer.toString();
  }
}

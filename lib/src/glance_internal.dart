import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/sampler.dart';

// typedef HandleDrawFrameEndCallback = void Function(
//     int beginFrameTimeInMillis, int drawFrameTimeInMillis);

// class GlanceWidgetBinding extends WidgetsFlutterBinding {
//   GlanceWidgetBinding._();

//   static GlanceWidgetBinding get instance =>
//       BindingBase.checkInstance(_instance);
//   static GlanceWidgetBinding? _instance;

//   int beginFrameTimeInMillis_ = 0;
//   HandleDrawFrameEndCallback? onHandleDrawFrameEndCallback_;

//   static GlanceWidgetBinding ensureInitialized() {
//     if (GlanceWidgetBinding._instance == null) {
//       GlanceWidgetBinding._();
//     }
//     return GlanceWidgetBinding.instance;
//   }

//   @override
//   void initInstances() {
//     super.initInstances();
//     _instance = this;
//   }

//   void setOnHandleDrawFrameEndCallback(HandleDrawFrameEndCallback? callback) {
//     onHandleDrawFrameEndCallback_ = callback;
//   }

//   @override
//   void handleBeginFrame(Duration? rawTimeStamp) {
//     // onHandleDrawFrameEndCallback_?.call(
//     //   beginFrameTimeInMillis_,
//     //   DateTime.now().millisecondsSinceEpoch,
//     // );

//     beginFrameTimeInMillis_ = DateTime.now().millisecondsSinceEpoch;
//     super.handleBeginFrame(rawTimeStamp);
//   }

//   @override
//   void handleDrawFrame() {
//     super.handleDrawFrame();

//     onHandleDrawFrameEndCallback_?.call(
//       beginFrameTimeInMillis_,
//       DateTime.now().millisecondsSinceEpoch,
//     );
//   }
// }

/// 16ms
const int _kDefaultJankThreshold = 16;

// typedef JankCallback = void Function(JankReport info);

// class StackTrace {
//   const StackTrace._(this.frames);
//   final List<NativeFrame> frames;

//   @override
//   String toString() {
//     return jsonEncode(toJson());
//   }

//   List<Map<String, Object?>> toJson() {
//     return frames.map((frame) {
//       return {
//         "pc": frame.pc.toString(),
//         "timestamp": frame.timestamp,
//         if (frame.module != null)
//           "baseAddress": frame.module!.baseAddress.toString(),
//         if (frame.module != null) "path": frame.module!.path,
//       };
//     }).toList();
//   }
// }

abstract class GlanceReporter<T> {
  void report(T info);
}

abstract class JankDetectedReporter extends GlanceReporter<JankReport> {}

abstract class GlanceStackTrace {
  // Map<String, Object?> toJson();
}

const glaceStackTraceHeaderLine =
    '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***';

const glaceStackTraceLineSpilt = ' ';

class _GlanceStackTraceImpl implements GlanceStackTrace {
  _GlanceStackTraceImpl(this.stackTraces);
  final List<NativeFrameTimeSpent> stackTraces;

  // static const _headerLine =
  //     '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***';
  static const _spilt = ' ';
  static const _baseAddrKey = 'base_addr';
  static const _pcKey = 'pc';

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
    stringBuffer.writeln(glaceStackTraceHeaderLine);
    for (int i = 0; i < stackTraces.length; ++i) {
      final stackTrace = stackTraces[i];
      final frame = stackTrace.frame;
      final spent = stackTrace.timestampInMacros;
      stringBuffer.write('#${i.toString().padLeft(3, '0')}');
      stringBuffer.write(glaceStackTraceLineSpilt);
      stringBuffer.write(frame.module!.baseAddress);
      stringBuffer.write(glaceStackTraceLineSpilt);
      stringBuffer.write(frame.pc);
      stringBuffer.write(glaceStackTraceLineSpilt);
      stringBuffer.write(spent);
      stringBuffer.write(glaceStackTraceLineSpilt);
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

class JankReport {
  const JankReport._({
    required this.stackTrace,
    required this.frameTiming,
  });
  // final List<NativeFrameTimeSpent> stackTraces;
  final GlanceStackTrace stackTrace;
  final FrameTiming frameTiming;

  // @override
  // String toString() {
  //   return jsonEncode(toJson());
  // }

  // JankReport fromJson(Map<String, Object?> json) {

  // }

  // Map<String, Object?> toJson() {
  //   return {
  //     'jankDuration': jankDuration.inMilliseconds,
  //     'stackTraces': stackTraces.map((e) {
  //       final frame = e.frame;
  //       final spent = e.timestampInMacros;
  //       return {
  //         "pc": frame.pc.toString(),
  //         "timestamp": frame.timestamp,
  //         if (frame.module != null)
  //           "baseAddress": frame.module!.baseAddress.toString(),
  //         if (frame.module != null) "path": frame.module!.path,
  //         'spent': spent,
  //       };
  //     }).toList()
  //   };
  // }
}

class GlanceConfiguration {
  const GlanceConfiguration({
    this.jankThreshold = _kDefaultJankThreshold,
    // this.jankCallback,
    this.reporters = const [],
  });
  final int jankThreshold;
  // final JankCallback? jankCallback;
  final List<GlanceReporter> reporters;
}

class Glance {
  Glance._();

  static Glance? _instance;
  static Glance get instance {
    _instance ??= Glance._();
    return _instance!;
  }

  Sampler? _sampleThread;

  // final List<JankCallback> _jankCallbacks = [];
  // final List<SlowFunctionsDetectedCallback>
  //     _slowFunctionsDetectedCallbackCallbacks = [];

  late List<GlanceReporter> reporters;

  Future<void> start({GlanceConfiguration? config}) async {
    final jankThreshold = config?.jankThreshold ?? _kDefaultJankThreshold;
    reporters = List.from(config?.reporters ?? []);

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

    _sampleThread ??= await Sampler.create();
    // _sampleThread?.addSlowFunctionsDetectedCallback((info) {
    //   for (final callback
    //       in List.from(_slowFunctionsDetectedCallbackCallbacks)) {
    //     callback(info);
    //   }
    // });

    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      if (_sampleThread == null) {
        return;
      }
      int now = DateTime.now().microsecondsSinceEpoch;
      print('DateTime.now(): $now');
      print('Timeline.now: ${Timeline.now}');
      for (int i = 0; i < timings.length; ++i) {
        final FrameTiming timing = timings[i];
        print(
            'FramePhase.vsyncStart: ${timing.timestampInMicroseconds(FramePhase.vsyncStart)}, FramePhase.rasterFinish: ${timing.timestampInMicroseconds(FramePhase.rasterFinish)}');
        print(
            'timing.buildDuration: ${timing.buildDuration.inMilliseconds}, timing.rasterDuration: ${timing.rasterDuration.inMilliseconds}, timing.totalSpan: ${timing.totalSpan.inMilliseconds}');
        //   print(
        //       'timing.timestampInMicroseconds(FramePhase.rasterFinish): ${timing.timestampInMicroseconds(FramePhase.rasterFinish)}');
        //   print(
        //       'timing.timestampInMicroseconds(FramePhase.buildStart): ${timing.timestampInMicroseconds(FramePhase.buildStart)}');
        final diff = timing.timestampInMicroseconds(FramePhase.rasterFinish) -
            timing.timestampInMicroseconds(FramePhase.buildStart);
        final totalSpan = timing.totalSpan.inMilliseconds;
        if (totalSpan > jankThreshold) {
          // report jank
          _report(timings, i);
          break;
        }
      }
    });
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
    int preIndex = index - 1;
    int nextIndex = index + 1;
    List<FrameTiming> reportTimings = [];
    // if (preIndex >= 0) {
    //   reportTimings.add(timings[preIndex]);
    // }
    reportTimings.add(timings[index]);
    // if (nextIndex < timings.length) {
    //   reportTimings.add(timings[nextIndex]);
    // }
    assert(reportTimings.isNotEmpty);

    // Request stacktraces
    final timestampRange = [
      reportTimings.first.timestampInMicroseconds(FramePhase.vsyncStart),
      reportTimings.last.timestampInMicroseconds(FramePhase.rasterFinish),
    ];

    assert(_sampleThread != null);
    final frames = await _sampleThread!.getSamples(timestampRange);
    final report = JankReport._(
      stackTrace: _GlanceStackTraceImpl(frames),
      frameTiming: timings[index],
    );

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

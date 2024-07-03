import 'dart:async';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance_impl.dart';

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

// /// 16ms
// const int _kDefaultJankThreshold = 16;

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

abstract class GlanceStackTrace {
  // Map<String, Object?> toJson();
}

abstract class GlanceReporter<T> {
  void report(T info);
}

abstract class JankDetectedReporter extends GlanceReporter<JankReport> {}

class JankReport {
  const JankReport({
    required this.stackTrace,
    required this.frameTimings,
  });
  // final List<NativeFrameTimeSpent> stackTraces;
  final GlanceStackTrace stackTrace;
  final List<FrameTiming> frameTimings;

  @override
  String toString() {
    return stackTrace.toString();
  }

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
    this.jankThreshold = kDefaultJankThreshold,
    // this.jankCallback,
    this.reporters = const [],
    this.modulePathFilters = kDefaultModulePathFilters,
    this.sampleRateInMilliseconds = kDefaultSampleRateInMilliseconds,
  });
  final int jankThreshold;
  // final JankCallback? jankCallback;
  final List<GlanceReporter> reporters;

  /// e.g., libapp.so, libflutter.so
  final List<String> modulePathFilters;

  final int sampleRateInMilliseconds;
}

abstract class Glance {
  Glance._();

  static Glance? _instance;
  static Glance get instance {
    _instance ??= GlanceImpl();
    return _instance!;
  }

  // Sampler? _sampleThread;

  // TimingsCallback? _timingsCallback;

  // // final List<JankCallback> _jankCallbacks = [];
  // // final List<SlowFunctionsDetectedCallback>
  // //     _slowFunctionsDetectedCallbackCallbacks = [];

  // late List<GlanceReporter> reporters;

  // bool _started = false;

  Future<void> start(
      {GlanceConfiguration config = const GlanceConfiguration()});
  //      async {
  //   if (_started) {
  //     return;
  //   }

  //   _started = true;
  //   final jankThreshold = config.jankThreshold;
  //   reporters = List.of(config.reporters, growable: false);

  //   // final binding = GlanceWidgetBinding.ensureInitialized();
  //   // binding.setOnHandleDrawFrameEndCallback(
  //   //     (int beginFrameTimeInMillis, int drawFrameTimeInMillis) {
  //   //   final diff = drawFrameTimeInMillis - beginFrameTimeInMillis;
  //   //   print('diff: $diff');
  //   //   if (diff > jankThreshold) {
  //   //     // report jank
  //   //     // _report(beginFrameTimeInMillis, drawFrameTimeInMillis);
  //   //   }
  //   //   _report(beginFrameTimeInMillis, drawFrameTimeInMillis);
  //   // });

  //   _sampleThread ??= await Sampler.create(SamplerConfig(
  //     jankThreshold: jankThreshold,
  //     modulePathFilters: config.modulePathFilters,
  //     sampleRateInMilliseconds: config.sampleRateInMilliseconds,
  //   ));
  //   // _sampleThread?.addSlowFunctionsDetectedCallback((info) {
  //   //   for (final callback
  //   //       in List.from(_slowFunctionsDetectedCallbackCallbacks)) {
  //   //     callback(info);
  //   //   }
  //   // });

  //   _timingsCallback ??= (List<FrameTiming> timings) {
  //     if (_sampleThread == null) {
  //       return;
  //     }
  //     // int now = DateTime.now().microsecondsSinceEpoch;
  //     final jankTimings = <FrameTiming>[];
  //     for (int i = 0; i < timings.length; ++i) {
  //       final FrameTiming timing = timings[i];
  //       // print(
  //       //     'FramePhase.vsyncStart: ${timing.timestampInMicroseconds(FramePhase.vsyncStart)}, FramePhase.rasterFinish: ${timing.timestampInMicroseconds(FramePhase.rasterFinish)}');
  //       // print(
  //       //     'timing.buildDuration: ${timing.buildDuration.inMilliseconds}, timing.rasterDuration: ${timing.rasterDuration.inMilliseconds}, timing.totalSpan: ${timing.totalSpan.inMilliseconds}');
  //       //   print(
  //       //       'timing.timestampInMicroseconds(FramePhase.rasterFinish): ${timing.timestampInMicroseconds(FramePhase.rasterFinish)}');
  //       //   print(
  //       //       'timing.timestampInMicroseconds(FramePhase.buildStart): ${timing.timestampInMicroseconds(FramePhase.buildStart)}');
  //       // final diff = timing.timestampInMicroseconds(FramePhase.rasterFinish) -
  //       //     timing.timestampInMicroseconds(FramePhase.buildStart);
  //       final totalSpan = timing.totalSpan.inMilliseconds;
  //       if (totalSpan > jankThreshold) {
  //         // report jank
  //         // _report(timings, i);
  //         // break;

  //         jankTimings.add(timing);
  //       }
  //     }

  //     if (jankTimings.isNotEmpty) {
  //       _report(jankTimings, 0);
  //     }
  //   };

  //   SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);
  // }

  Future<void> end();
  //  async {
  //   if (!_started) {
  //     return;
  //   }
  //   SchedulerBinding.instance.removeTimingsCallback(_timingsCallback!);
  //   _timingsCallback = null;
  //   _sampleThread?.close();
  // }

  // // Future<void> _report(int startTimestamp, int endTimestamp) async {
  // //   if (_sampleThread == null) {
  // //     return;
  // //   }
  // //   // Report the nearest 3 timings if possiable.
  // //   // int preIndex = index - 1;
  // //   // int nextIndex = index + 1;
  // //   // List<FrameTiming> reportTimings = [];
  // //   // if (preIndex >= 0) {
  // //   //   reportTimings.add(timings[preIndex]);
  // //   // }
  // //   // reportTimings.add(timings[index]);
  // //   // if (nextIndex < timings.length) {
  // //   //   reportTimings.add(timings[nextIndex]);
  // //   // }
  // //   // assert(reportTimings.isNotEmpty);

  // //   // // Request stacktraces
  // //   final timestampRange = [startTimestamp, endTimestamp];

  // //   assert(_sampleThread != null);
  // //   final frames = await _sampleThread!.getSamples(timestampRange);
  // //   final stacktrace = JankReport._(
  // //     stackTraces: frames,
  // //     jankDuration: Duration(milliseconds: endTimestamp - startTimestamp),
  // //   );

  // //   final callbacks = List.from(_jankCallbacks);
  // //   for (final callback in callbacks) {
  // //     callback(stacktrace);
  // //   }
  // // }

  // Future<void> _report(List<FrameTiming> timings, int index) async {
  //   // Report the nearest 3 timings if possiable.
  //   // int preIndex = index - 1;
  //   // int nextIndex = index + 1;
  //   // List<FrameTiming> reportTimings = timings;
  //   // if (preIndex >= 0) {
  //   //   reportTimings.add(timings[preIndex]);
  //   // }
  //   // reportTimings.add(timings[index]);
  //   // if (nextIndex < timings.length) {
  //   //   reportTimings.add(timings[nextIndex]);
  //   // }
  //   // assert(reportTimings.isNotEmpty);

  //   // Request stacktraces
  //   final timestampRange = [
  //     timings.first.timestampInMicroseconds(FramePhase.vsyncStart),
  //     timings.last.timestampInMicroseconds(FramePhase.rasterFinish),
  //   ];

  //   assert(_sampleThread != null);
  //   final frames = await _sampleThread!.getSamples(timestampRange);
  //   if (frames.isEmpty) {
  //     return;
  //   }
  //   final report = JankReport._(
  //     stackTrace: GlanceStackTraceImpl(frames),
  //     frameTimings: timings,
  //   );

  //   // final callbacks = List.from(_jankCallbacks);
  //   // for (final callback in callbacks) {
  //   //   callback(stacktrace);
  //   // }

  //   for (final reporter in reporters) {
  //     reporter.report(report);
  //   }
  // }

  // void addJankCallback(JankCallback callback) {
  //   _jankCallbacks.add(callback);
  // }

  // void addSlowFunctionsDetectedCallback(
  //     SlowFunctionsDetectedCallback callback) {
  //   _slowFunctionsDetectedCallbackCallbacks.add(callback);
  // }
}

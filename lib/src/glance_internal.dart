import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/sampler.dart';

typedef HandleDrawFrameEndCallback = void Function(
    int beginFrameTimeInMillis, int drawFrameTimeInMillis);

class GlanceWidgetBinding extends WidgetsFlutterBinding {
  GlanceWidgetBinding._();

  static GlanceWidgetBinding get instance =>
      BindingBase.checkInstance(_instance);
  static GlanceWidgetBinding? _instance;

  int beginFrameTimeInMillis_ = 0;
  HandleDrawFrameEndCallback? onHandleDrawFrameEndCallback_;

  static GlanceWidgetBinding ensureInitialized() {
    if (GlanceWidgetBinding._instance == null) {
      GlanceWidgetBinding._();
    }
    return GlanceWidgetBinding.instance;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  void setOnHandleDrawFrameEndCallback(HandleDrawFrameEndCallback? callback) {
    onHandleDrawFrameEndCallback_ = callback;
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    // onHandleDrawFrameEndCallback_?.call(
    //   beginFrameTimeInMillis_,
    //   DateTime.now().millisecondsSinceEpoch,
    // );

    beginFrameTimeInMillis_ = DateTime.now().millisecondsSinceEpoch;
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void handleDrawFrame() {
    super.handleDrawFrame();

    onHandleDrawFrameEndCallback_?.call(
      beginFrameTimeInMillis_,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 16ms
const int _kDefaultJankThreshold = 16;

typedef JankCallback = void Function(JankReport info);

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
  Map<String, Object?> toJson();
}

class _GlanceStackTraceImpl implements GlanceStackTrace {
  @override
  Map<String, Object?> toJson() {
    // TODO: implement toJson
    throw UnimplementedError();
  }

  @override
  String toString() {
    // TODO: implement toString
    return super.toString();
  }
}

class JankReport {
  const JankReport._({
    required this.stackTraces,
    required this.jankDuration,
  });
  final List<NativeFrameTimeSpent> stackTraces;
  final Duration jankDuration;

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  // JankReport fromJson(Map<String, Object?> json) {

  // }

  Map<String, Object?> toJson() {
    return {
      'jankDuration': jankDuration.inMilliseconds,
      'stackTraces': stackTraces.map((e) {
        final frame = e.frame;
        final spent = e.timestampInMacros;
        return {
          "pc": frame.pc.toString(),
          "timestamp": frame.timestamp,
          if (frame.module != null)
            "baseAddress": frame.module!.baseAddress.toString(),
          if (frame.module != null) "path": frame.module!.path,
          'spent': spent,
        };
      }).toList()
    };
  }
}

class GlanceConfiguration {
  const GlanceConfiguration({
    this.jankThreshold = _kDefaultJankThreshold,
    this.jankCallback,
  });
  final int jankThreshold;
  final JankCallback? jankCallback;
}

class Glance {
  Glance._();

  static Glance? _instance;
  static Glance get instance {
    _instance ??= Glance._();
    return _instance!;
  }

  Sampler? _sampleThread;

  final List<JankCallback> _jankCallbacks = [];
  final List<SlowFunctionsDetectedCallback>
      _slowFunctionsDetectedCallbackCallbacks = [];

  Future<void> start({GlanceConfiguration? config}) async {
    final jankThreshold = config?.jankThreshold ?? _kDefaultJankThreshold;

    final binding = GlanceWidgetBinding.ensureInitialized();
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
    final stacktrace = JankReport._(
      stackTraces: frames,
      jankDuration: Duration(microseconds: 0),
    );

    final callbacks = List.from(_jankCallbacks);
    for (final callback in callbacks) {
      callback(stacktrace);
    }
  }

  void addJankCallback(JankCallback callback) {
    _jankCallbacks.add(callback);
  }

  void addSlowFunctionsDetectedCallback(
      SlowFunctionsDetectedCallback callback) {
    _slowFunctionsDetectedCallbackCallbacks.add(callback);
  }
}



// import 'dart:async';
// import 'dart:convert';
// import 'dart:isolate';

// void main() async {
//   final _SampleThread = await _SampleThread.spawn();
//   print(await _SampleThread.parseJson('{"key":"value"}'));
//   print(await _SampleThread.parseJson('"banana"'));
//   print(await _SampleThread.parseJson('[true, false, null, 1, "string"]'));
//   print(
//       await Future.wait([_SampleThread.parseJson('"yes"'), _SampleThread.parseJson('"no"')]));
//   _SampleThread.close();
// }


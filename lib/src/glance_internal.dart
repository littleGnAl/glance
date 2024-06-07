import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glance/src/collect_stack.dart';

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

typedef JankCallback = void Function(StackTrace stacktrace);

class StackTrace {
  const StackTrace._(this.frames);
  final List<NativeFrame> frames;

  @override
  String toString() {
    return jsonEncode(frames.map((frame) {
      return {
        "pc": frame.pc.toString(),
        "timestamp": frame.timestamp,
        if (frame.module != null)
          "baseAddress": frame.module!.baseAddress.toString(),
        if (frame.module != null) "path": frame.module!.path,
      };
    }).toList());
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

  SampleThread? _sampleThread;

  final List<JankCallback> _jankCallbacks = [];

  Future<void> start({GlanceConfiguration? config}) async {
    final jankThreshold = config?.jankThreshold ?? _kDefaultJankThreshold;

    final binding = GlanceWidgetBinding.ensureInitialized();
    binding.setOnHandleDrawFrameEndCallback(
        (int beginFrameTimeInMillis, int drawFrameTimeInMillis) {
      final diff = drawFrameTimeInMillis - beginFrameTimeInMillis;
      if (diff > jankThreshold) {
        // report jank
        _report(beginFrameTimeInMillis, drawFrameTimeInMillis);
      }
    });

    _sampleThread ??= await SampleThread.spawn();

    // SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    //   int now = DateTime.now().microsecondsSinceEpoch;
    //   print('now: $now');
    //   for (int i = 0; i < timings.length; ++i) {
    //     final timing = timings[i];
    //     print('timing: ${timing.toString()}');
    //     print(
    //         'timing.timestampInMicroseconds(FramePhase.rasterFinish): ${timing.timestampInMicroseconds(FramePhase.rasterFinish)}');
    //     print(
    //         'timing.timestampInMicroseconds(FramePhase.buildStart): ${timing.timestampInMicroseconds(FramePhase.buildStart)}');
    //     final diff = timing.timestampInMicroseconds(FramePhase.rasterFinish) -
    //         timing.timestampInMicroseconds(FramePhase.buildStart);
    //     final totalSpan = timing.totalSpan.inMilliseconds;
    //     if (diff > jankThreshold) {
    //       // report jank
    //       _report(timings, i);
    //       break;
    //     }
    //   }
    // });
  }

  Future<void> _report(int startTimestamp, int endTimestamp) async {
    // Report the nearest 3 timings if possiable.
    // int preIndex = index - 1;
    // int nextIndex = index + 1;
    // List<FrameTiming> reportTimings = [];
    // if (preIndex >= 0) {
    //   reportTimings.add(timings[preIndex]);
    // }
    // reportTimings.add(timings[index]);
    // if (nextIndex < timings.length) {
    //   reportTimings.add(timings[nextIndex]);
    // }
    // assert(reportTimings.isNotEmpty);

    // // Request stacktraces
    final timestampRange = [startTimestamp, endTimestamp];

    assert(_sampleThread != null);
    final frames = await _sampleThread!.getSamples(timestampRange);
    print('hhhh');
    final stacktrace = StackTrace._(frames);

    final callbacks = List.from(_jankCallbacks);
    for (final callback in callbacks) {
      callback(stacktrace);
    }
  }

  // Future<void> _report(List<FrameTiming> timings, int index) async {
  //   // Report the nearest 3 timings if possiable.
  //   int preIndex = index - 1;
  //   int nextIndex = index + 1;
  //   List<FrameTiming> reportTimings = [];
  //   if (preIndex >= 0) {
  //     reportTimings.add(timings[preIndex]);
  //   }
  //   reportTimings.add(timings[index]);
  //   if (nextIndex < timings.length) {
  //     reportTimings.add(timings[nextIndex]);
  //   }
  //   assert(reportTimings.isNotEmpty);

  //   // Request stacktraces
  //   final timestampRange = [
  //     reportTimings.first.timestampInMicroseconds(FramePhase.buildStart),
  //     reportTimings.last.timestampInMicroseconds(FramePhase.rasterFinish),
  //   ];

  //   assert(_sampleThread != null);
  //   final frames = await _sampleThread!.getSamples(timestampRange);
  //   print('hhhh');
  //   final stacktrace = StackTrace._(frames);

  //   final callbacks = List.from(_jankCallbacks);
  //   for (final callback in callbacks) {
  //     callback(stacktrace);
  //   }
  // }

  void addJankCallback(JankCallback callback) {
    _jankCallbacks.add(callback);
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


import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:glance/src/collect_stack.dart';

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
    _sampleThread ??= await SampleThread.spawn();

    final jankThreshold = config?.jankThreshold ?? _kDefaultJankThreshold;
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      int now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < timings.length; ++i) {
        final timing = timings[i];
        final diff = timing.timestampInMicroseconds(FramePhase.rasterFinish) -
            timing.timestampInMicroseconds(FramePhase.buildStart);
        final totalSpan = timing.totalSpan.inMilliseconds;
        if (diff > jankThreshold) {
          // report jank
          _report(timings, i);
          break;
        }
      }
    });
  }

  Future<void> _report(List<FrameTiming> timings, int index) async {
    // Report the nearest 3 timings if possiable.
    int preIndex = index - 1;
    int nextIndex = index + 1;
    List<FrameTiming> reportTimings = [];
    if (preIndex >= 0) {
      reportTimings.add(timings[preIndex]);
    }
    reportTimings.add(timings[index]);
    if (nextIndex < timings.length) {
      reportTimings.add(timings[nextIndex]);
    }
    assert(reportTimings.isNotEmpty);

    // Request stacktraces
    final timestampRange = [
      reportTimings.first.timestampInMicroseconds(FramePhase.buildStart),
      reportTimings.last.timestampInMicroseconds(FramePhase.rasterFinish),
    ];

    assert(_sampleThread != null);
    final frames = await _sampleThread!.getSamples(timestampRange);
    print('hhhh');
    final stacktrace = StackTrace._(frames);

    final callbacks = List.from(_jankCallbacks);
    for (final callback in callbacks) {
      callback(stacktrace);
    }
  }

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


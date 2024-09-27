import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart' show BinaryMessenger, MessageHandler;
import 'package:flutter/widgets.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance.dart';
import 'package:glance/src/sampler.dart';
import 'package:meta/meta.dart' show visibleForTesting, internal;

/// Implementation of [Glance]
class GlanceImpl implements Glance {
  GlanceImpl();

  @visibleForTesting
  GlanceImpl.forTesting(Sampler sampler) : _sampler = sampler;

  Sampler? _sampler;

  CheckJankCallback? _checkJank;

  late List<GlanceReporter> _reporters;

  bool _started = false;

  GlanceStackTraceImpl? _previousStackTrace;

  DartStackTraceInfo? _dartStackTraceInfo;

  @override
  Future<void> start(
      {GlanceConfiguration config = const GlanceConfiguration()}) async {
    if (_started) {
      return;
    }

    _started = true;
    _dartStackTraceInfo ??=
        parseDartStackTraceInfo(StackTrace.current.toString());

    final jankThreshold = config.jankThreshold;
    final sampleRateInMilliseconds = config.sampleRateInMilliseconds;
    _reporters = List.of(config.reporters, growable: false);
    final List<String> modulePathFilters = config.modulePathFilters;

    _sampler ??= await Sampler.create(SamplerConfig(
      jankThreshold: jankThreshold,
      modulePathFilters: modulePathFilters,
      sampleRateInMilliseconds: sampleRateInMilliseconds,
    ));

    _checkJank = (int start, int end) {
      if (_sampler == null) {
        return;
      }

      final totalSpan = (end - start) / 1000.0;
      if (totalSpan > jankThreshold) {
        _report(start, end);
      }
    };
    GlanceWidgetBinding.instance.onCheckJank = _checkJank!;
  }

  @override
  Future<void> end() async {
    if (!_started) {
      return;
    }
    GlanceWidgetBinding.instance.onCheckJank = null;
    _checkJank = null;
    _sampler?.close();
    _sampler = null;
    _dartStackTraceInfo = null;
  }

  Future<void> _report(int start, int end) async {
    final timestampRange = [start, end];

    assert(_sampler != null);
    final frames = await _sampler!.getSamples(timestampRange);
    if (frames.isEmpty) {
      return;
    }

    final straceTrace = GlanceStackTraceImpl(
        frames, _dartStackTraceInfo ?? const DartStackTraceInfo(0, []));
    if (straceTrace == _previousStackTrace) {
      return;
    }

    final report = JankReport(stackTrace: straceTrace);

    _previousStackTrace = straceTrace;

    for (final reporter in _reporters) {
      reporter.report(report);
    }
  }

  /// Parse the Dart [StackTrace.current], get the header contents, and parse the
  /// `isolate_instructions` value.
  ///
  /// We can reconstruct the glance stack traces using this information later.
  @visibleForTesting
  DartStackTraceInfo? parseDartStackTraceInfo(String dartStackTrace) {
    // The dart [StackTrace.current] in string, for example
    // ```
    // *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
    // pid: 3081, tid: 6164033536, name io.flutter.1.ui
    // os: ios arch: arm64 comp: no sim: no
    // build_id: 'a8a967193ee33ac7a4852e7160590972'
    // isolate_dso_base: 1016b8000, vm_dso_base: 1016b8000
    // isolate_instructions: 1016c6700, vm_instructions: 1016bc000
    //     #00 abs 00000001018423fb _kDartIsolateSnapshotInstructions+0x17bcfb
    // ```

    final dartStackTraceLines = dartStackTrace.split('\n');
    int isolateInstructions = 0;
    List<String> dartStackTraceHeaderLines = [];

    bool foundHeaderStart = false;
    bool foundHeaderEnd = false;
    String dartStackTraceHeaderEndLine = '';
    for (int i = 0; i < dartStackTraceLines.length; ++i) {
      final line = dartStackTraceLines[i].trim();
      if (line == kGlanceStackTraceHeaderLine) {
        foundHeaderStart = true;
      }

      if (!foundHeaderStart) {
        continue;
      }

      dartStackTraceHeaderLines.add(line);

      if (line.startsWith('isolate_instructions:')) {
        dartStackTraceHeaderEndLine = line;
        foundHeaderEnd = true;
      }

      if (foundHeaderEnd) {
        break;
      }
    }

    if (dartStackTraceHeaderEndLine.isEmpty) {
      return null;
    }

    // e.g.,
    // isolate_instructions: 1016c6700, vm_instructions: 1016bc000
    final isolateInstructionsInString =
        dartStackTraceHeaderEndLine.split(',')[0].split(':')[1].trim();

    isolateInstructions =
        int.tryParse(isolateInstructionsInString, radix: 16) ?? 0;

    return DartStackTraceInfo(isolateInstructions, dartStackTraceHeaderLines);
  }
}

class DartStackTraceInfo {
  const DartStackTraceInfo(
      this.isolateInstructions, this.dartStackTraceHeaderLines);
  final int isolateInstructions;
  final List<String> dartStackTraceHeaderLines;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    return other is DartStackTraceInfo &&
        isolateInstructions == other.isolateInstructions &&
        dartStackTraceHeaderLines == other.dartStackTraceHeaderLines;
  }

  @override
  int get hashCode => Object.hash(
      isolateInstructions, Object.hashAll(dartStackTraceHeaderLines));
}

/// Implementation of [StackTrace] of glance.
class GlanceStackTraceImpl implements StackTrace {
  const GlanceStackTraceImpl(this.stackTraces, this.dartStackTraceInfo);
  final List<AggregatedNativeFrame> stackTraces;

  final DartStackTraceInfo dartStackTraceInfo;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    return other is GlanceStackTraceImpl &&
        dartStackTraceInfo == other.dartStackTraceInfo &&
        listEquals(stackTraces, other.stackTraces);
  }

  @override
  int get hashCode =>
      Object.hash(dartStackTraceInfo, Object.hashAll(stackTraces));

  /// Reconstructs the Dart stack trace in the following pattern:
  /// ```
  /// *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
  /// pid: 3081, tid: 6164033536, name io.flutter.1.ui
  /// os: ios arch: arm64 comp: no sim: no
  /// build_id: 'a8a967193ee33ac7a4852e7160590972'
  /// isolate_dso_base: 1016b8000, vm_dso_base: 1016b8000
  /// isolate_instructions: 1016c6700, vm_instructions: 1016bc000
  ///     #00 abs <pc> _kDartIsolateSnapshotInstructions+<pc_offset>
  /// ```
  ///
  /// If the [DartStackTraceInfo] cannot be parsed with [parseDartStackTraceInfo], it will omit
  /// the header contents and `<pc_offset>`, returning the pattern like:
  /// ```
  /// *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
  ///     #00 abs <pc> _kDartIsolateSnapshotInstructions
  /// ```
  @override
  String toString() {
    final isolateInstructions = dartStackTraceInfo.isolateInstructions;
    final dartStackTraceHeaderLines =
        dartStackTraceInfo.dartStackTraceHeaderLines;

    final stringBuffer = StringBuffer();

    if (dartStackTraceHeaderLines.isNotEmpty) {
      stringBuffer.writeln(dartStackTraceHeaderLines.join('\n'));
    } else {
      stringBuffer.writeln(kGlanceStackTraceHeaderLine);
    }

    for (int i = 0; i < stackTraces.length; ++i) {
      final stackTrace = stackTraces[i];
      final frame = stackTrace.frame;

      final pc = frame.pc;
      // Reference to the Dart SDK's `StackTrace.current` implementation
      // https://github.com/dart-lang/sdk/blob/fff7b0589c5b39598b864533ca5fdabb60a8237c/runtime/vm/object.cc#L26259
      // Calculate the pc offset using `pc - isolate_instructions`.
      int pcOffset = pc - isolateInstructions;
      if (pcOffset < 0) {
        continue;
      }

      stringBuffer.write('    ');
      stringBuffer.write('#${i.toString().padLeft(2, '0')}');
      stringBuffer.write(kGlanceStackTraceLineSpilt);
      stringBuffer.write('abs');
      stringBuffer.write(kGlanceStackTraceLineSpilt);
      // e.g.,
      // #00 abs <pc> _kDartIsolateSnapshotInstructions+<pc_offset>
      stringBuffer.write(frame.pc.toRadixString(16).padLeft(16, '0'));
      stringBuffer.write(kGlanceStackTraceLineSpilt);
      stringBuffer.write('_kDartIsolateSnapshotInstructions');
      if (isolateInstructions != 0) {
        stringBuffer.write('+0x${pcOffset.toRadixString(16)}');
      }

      stringBuffer.writeln();
    }

    return stringBuffer.toString();
  }
}

typedef HandleDrawFrameEndCallback = void Function(
    int beginFrameTimeInMillis, int drawFrameTimeInMillis);

typedef CheckJankCallback = void Function(int start, int end);

/// Besides the build phase check ([handleBeginFrame] to [handleDrawFrame]), we only
/// override the functions that handle callbacks from the [PlatformDispatcher].
/// Other callbacks are handled by the channel called ([_DefaultBinaryMessengerProxy]).
mixin GlanceWidgetBindingMixin on WidgetsFlutterBinding {
  int _beginFrameStartInMicros = 0;

  CheckJankCallback? _onCheckJank;
  @internal
  CheckJankCallback? get onCheckJank => _onCheckJank;
  @internal
  set onCheckJank(CheckJankCallback? callback) {
    _onCheckJank = callback;
  }

  @visibleForTesting
  T traceFunctionCall<T>(T Function() func) {
    int start = Timeline.now;
    final ret = func();
    // Only check jank if not in build phase, because if it is in buid phase,
    // the jank has been checked by the build phase jank check
    if (schedulerPhase == SchedulerPhase.idle) {
      _onCheckJank?.call(start, Timeline.now);
    }

    return ret;
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _beginFrameStartInMicros = Timeline.now;
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void handleDrawFrame() {
    super.handleDrawFrame();
    _onCheckJank?.call(_beginFrameStartInMicros, Timeline.now);
  }

  @override
  BinaryMessenger createBinaryMessenger() {
    return _DefaultBinaryMessengerProxy(
      super.createBinaryMessenger(),
      (start, end) {
        _onCheckJank?.call(start, end);
      },
    );
  }

  @override
  void handlePointerEvent(PointerEvent event) {
    traceFunctionCall(() {
      super.handlePointerEvent(event);
    });
  }

  @override
  void handleMetricsChanged() {
    traceFunctionCall(() => super.handleMetricsChanged());
  }

  @override
  void handleTextScaleFactorChanged() {
    traceFunctionCall(() => super.handleTextScaleFactorChanged());
  }

  @override
  void handlePlatformBrightnessChanged() {
    traceFunctionCall(() => super.handlePlatformBrightnessChanged());
  }

  @override
  void dispatchLocalesChanged(List<Locale>? locales) {
    traceFunctionCall(() => super.dispatchLocalesChanged(locales));
  }

  @override
  void handleAccessibilityFeaturesChanged() {
    traceFunctionCall(() => super.handleAccessibilityFeaturesChanged());
  }
}

/// A proxy for the `_DefaultBinaryMessenger` to trace the time consumed in the
/// [MessageHandler] set by the user.
class _DefaultBinaryMessengerProxy implements BinaryMessenger {
  const _DefaultBinaryMessengerProxy(this._proxy, this._onCheckJank);
  final BinaryMessenger _proxy;
  final CheckJankCallback _onCheckJank;
  @override
  Future<void> handlePlatformMessage(String channel, ByteData? data,
      PlatformMessageResponseCallback? callback) {
    // ignore: deprecated_member_use
    return _proxy.handlePlatformMessage(channel, data, callback);
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    return _proxy.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    _proxy.setMessageHandler(
        channel,
        handler == null
            ? handler
            : (ByteData? message) {
                final start = Timeline.now;
                return handler(message)!.whenComplete(() {
                  _onCheckJank(start, Timeline.now);
                });
              });
  }
}
